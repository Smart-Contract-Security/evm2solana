// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "./interfaces/IArtvybeCollectionV3.sol";

/// @title ArtvybeCollectionV3
/// @notice V3 = V2 (mutable maxSupply, lockable) + on-chain Merkle allowlist
///         with mutable root, owner toggle, per-wallet cap, optional discount,
///         and an optional auto-flip timestamp. The factory passes an
///         `AllowlistConfig` struct so the constructor stays under the
///         stack-too-deep limit.
contract ArtvybeCollectionV3 is
    ERC721,
    ERC721Enumerable,
    ERC2981,
    Ownable,
    ReentrancyGuard,
    IArtvybeCollectionV3
{
    using SafeERC20 for IERC20;

    // -----------------------------------------------------------------
    // Storage (V1/V2 compatible layout, then V3 additions)
    // -----------------------------------------------------------------

    uint256 public maxSupply;

    address public mintingCurrency;
    address public immutable platformTreasury;

    uint96 public creatorFeeBps;
    uint96 public immutable platformFeeBps;

    uint256 public mintPrice;
    bool public mintingEnabled;
    bool public batchMintingAllowed;
    string public baseTokenURI;
    uint256 public currentSupply;
    uint256 public mintStartTime;

    bool public supplyLocked;

    // Allowlist storage (V3)
    bytes32 public allowlistMerkleRoot;
    bool public allowlistEnabled;
    /// @dev `0` means no cap.
    uint256 public allowlistWalletLimit;
    /// @dev `0` means use the public `mintPrice` for allowlist mints.
    uint256 public allowlistMintPrice;
    /// @dev `0` means the allowlist phase only ends when the owner flips
    ///      `allowlistEnabled` off or calls `endAllowlistEarly`.
    uint256 public allowlistEnd;
    /// @dev `0` means public mint opens the moment the allowlist phase
    ///      ends (whichever way it ends). Otherwise public mint waits
    ///      until `block.timestamp >= publicStart`.
    uint256 public publicStart;
    mapping(address => uint256) public allowlistMinted;

    // -----------------------------------------------------------------
    // Errors
    // -----------------------------------------------------------------

    error MintingDisabled();
    error BatchMintingDisabled();
    error ExceedsMaxSupply();
    error InvalidQuantity();
    error InsufficientPayment();
    error TransferFailed();
    error InvalidTokenId();
    error ZeroAddress();
    error InsufficientBalance();
    error InvalidCreatorFeeBps();
    error InvalidParameters();
    error MintingNotStarted();

    error SupplyAlreadyLocked();
    error InvalidExtension();

    // V3
    error AllowlistInactive();
    error AllowlistOnly();
    error InvalidProof();
    error WalletLimitExceeded();
    error PublicNotStarted();

    // -----------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------

    /// @notice Mirrors `IArtvybeCollectionV3.AllowlistInit` so the factory can
    ///         pass allowlist params without blowing the stack. All-zero
    ///         struct = "no allowlist", behaves identically to V2.
    struct AllowlistInit {
        bytes32 merkleRoot;
        bool enabled;
        uint256 walletLimit;
        uint256 mintPrice;
        uint256 allowlistEnd;
        uint256 publicStart;
    }

    constructor(
        string memory name,
        string memory symbol,
        uint256 _maxSupply,
        uint96 _creatorFeeBps,
        address _mintingCurrency,
        uint256 _initialMintPrice,
        bool _batchMintingAllowed,
        string memory _baseTokenURI,
        address creator,
        address _platformTreasury,
        uint96 _platformFeeBps,
        uint256 _mintStartTime,
        AllowlistInit memory allowlistInit
    ) ERC721(name, symbol) Ownable(creator) {
        if (_platformTreasury == address(0)) revert ZeroAddress();
        if (_creatorFeeBps > 1000) revert InvalidCreatorFeeBps();

        maxSupply = _maxSupply;
        creatorFeeBps = _creatorFeeBps;
        mintingCurrency = _mintingCurrency;
        platformTreasury = _platformTreasury;
        platformFeeBps = _platformFeeBps;

        mintPrice = _initialMintPrice;
        batchMintingAllowed = _batchMintingAllowed;
        baseTokenURI = _baseTokenURI;
        mintingEnabled = true;
        currentSupply = 0;
        mintStartTime = _mintStartTime;

        _setDefaultRoyalty(creator, _creatorFeeBps);

        // Allowlist init — caller is responsible for sane values; we only
        // refuse the obvious self-contradictions to keep gas low.
        if (allowlistInit.enabled && allowlistInit.merkleRoot == bytes32(0)) {
            // Enabling allowlist without a root means literally nobody can
            // mint during the AL phase. Almost always a misconfig.
            revert InvalidParameters();
        }
        allowlistMerkleRoot = allowlistInit.merkleRoot;
        allowlistEnabled = allowlistInit.enabled;
        allowlistWalletLimit = allowlistInit.walletLimit;
        allowlistMintPrice = allowlistInit.mintPrice;
        allowlistEnd = allowlistInit.allowlistEnd;
        publicStart = allowlistInit.publicStart;
    }

    // -----------------------------------------------------------------
    // Public mint (V1 surface, gated against allowlist phase)
    // -----------------------------------------------------------------

    function mint(address to, uint256 quantity)
        external
        payable
        nonReentrant
    {
        if (!mintingEnabled) revert MintingDisabled();
        if (block.timestamp < mintStartTime) revert MintingNotStarted();
        if (isAllowlistPhase()) revert AllowlistOnly();
        if (publicStart != 0 && block.timestamp < publicStart) revert PublicNotStarted();
        if (quantity == 0) revert InvalidQuantity();
        if (to == address(0)) revert ZeroAddress();
        if (quantity > 1 && !batchMintingAllowed) revert BatchMintingDisabled();
        if (currentSupply + quantity > maxSupply) revert ExceedsMaxSupply();

        uint256 totalCost = mintPrice * quantity;
        _settlePayment(totalCost);
        _mintBatch(to, quantity, mintPrice);
    }

    // -----------------------------------------------------------------
    // Allowlist mint
    // -----------------------------------------------------------------

    function allowlistMint(uint256 quantity, bytes32[] calldata proof)
        external
        payable
        nonReentrant
    {
        if (!mintingEnabled) revert MintingDisabled();
        if (block.timestamp < mintStartTime) revert MintingNotStarted();
        if (!allowlistEnabled) revert AllowlistInactive();
        if (allowlistEnd != 0 && block.timestamp >= allowlistEnd) revert AllowlistInactive();
        if (allowlistMerkleRoot == bytes32(0)) revert AllowlistInactive();
        if (quantity == 0) revert InvalidQuantity();
        if (quantity > 1 && !batchMintingAllowed) revert BatchMintingDisabled();
        if (currentSupply + quantity > maxSupply) revert ExceedsMaxSupply();

        // Per-wallet cap (0 = no cap).
        uint256 alreadyMinted = allowlistMinted[msg.sender];
        if (
            allowlistWalletLimit != 0 &&
            alreadyMinted + quantity > allowlistWalletLimit
        ) {
            revert WalletLimitExceeded();
        }

        // Verify proof against `keccak256(abi.encodePacked(msg.sender))`.
        // This is the canonical Merkle leaf format for allowlist trees and
        // matches OpenZeppelin's reference implementation.
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        if (!MerkleProof.verifyCalldata(proof, allowlistMerkleRoot, leaf)) {
            revert InvalidProof();
        }

        uint256 effectivePrice = allowlistMintPrice == 0
            ? mintPrice
            : allowlistMintPrice;
        uint256 totalCost = effectivePrice * quantity;

        _settlePayment(totalCost);

        allowlistMinted[msg.sender] = alreadyMinted + quantity;

        _mintBatch(msg.sender, quantity, effectivePrice);
        emit AllowlistMint(msg.sender, quantity, effectivePrice);
    }

    // -----------------------------------------------------------------
    // Owner controls
    // -----------------------------------------------------------------

    function setAllowlistRoot(bytes32 newRoot) external onlyOwner {
        bytes32 old = allowlistMerkleRoot;
        allowlistMerkleRoot = newRoot;
        emit AllowlistRootUpdated(old, newRoot);
    }

    function setAllowlistEnabled(bool enabled) external onlyOwner {
        // Catch the trap where someone enables allowlist without ever setting
        // a root — that's a footgun, never legitimate.
        if (enabled && allowlistMerkleRoot == bytes32(0)) {
            revert InvalidParameters();
        }
        allowlistEnabled = enabled;
        emit AllowlistEnabledUpdated(enabled);
    }

    function setAllowlistConfig(
        uint256 walletLimit,
        uint256 newMintPrice,
        uint256 newAllowlistEnd,
        uint256 newPublicStart
    ) external onlyOwner {
        // walletLimit and newMintPrice are stored verbatim — caller asks for
        // 0 walletLimit if they want "no cap", or 0 mintPrice if they want
        // "use public price". newAllowlistEnd / newPublicStart are absolute
        // timestamps; passing 0 means "remove the auto-flip / public start".
        allowlistWalletLimit = walletLimit;
        allowlistMintPrice = newMintPrice;
        allowlistEnd = newAllowlistEnd;
        publicStart = newPublicStart;
        emit AllowlistConfigUpdated(
            walletLimit,
            newMintPrice,
            newAllowlistEnd,
            newPublicStart
        );
    }

    function endAllowlistEarly() external onlyOwner {
        allowlistEnabled = false;
        // Force the public phase to start now so creators don't have to chase
        // a separate setAllowlistConfig() call to actually open public mint.
        publicStart = block.timestamp;
        allowlistEnd = block.timestamp;
        emit AllowlistEnabledUpdated(false);
        emit AllowlistEndedEarly(block.timestamp);
    }

    function isAllowlistPhase() public view returns (bool) {
        if (!allowlistEnabled) return false;
        if (allowlistMerkleRoot == bytes32(0)) return false;
        if (allowlistEnd != 0 && block.timestamp >= allowlistEnd) return false;
        if (block.timestamp < mintStartTime) return false;
        return true;
    }

    // -----------------------------------------------------------------
    // V2 supply controls (carried over)
    // -----------------------------------------------------------------

    function extendMaxSupply(uint256 additional) external onlyOwner {
        if (supplyLocked) revert SupplyAlreadyLocked();
        if (additional == 0) revert InvalidExtension();

        uint256 oldCap = maxSupply;
        uint256 newCap = oldCap + additional;
        maxSupply = newCap;
        emit MaxSupplyExtended(oldCap, newCap);
    }

    function lockSupply() external onlyOwner {
        if (supplyLocked) revert SupplyAlreadyLocked();
        supplyLocked = true;
        emit SupplyLocked(maxSupply);
    }

    function version() external pure returns (string memory) {
        return "v3";
    }

    // -----------------------------------------------------------------
    // V1 setters (carried over)
    // -----------------------------------------------------------------

    function setMintPrice(uint256 newPrice) external onlyOwner {
        uint256 oldPrice = mintPrice;
        mintPrice = newPrice;
        emit MintPriceUpdated(oldPrice, newPrice);
    }

    function setMintingEnabled(bool enabled) external onlyOwner {
        mintingEnabled = enabled;
        emit MintingToggled(enabled);
    }

    function setBatchMinting(bool enabled) external onlyOwner {
        batchMintingAllowed = enabled;
        emit BatchMintingToggled(enabled);
    }

    function setBaseURI(string memory newURI) external onlyOwner {
        string memory oldURI = baseTokenURI;
        baseTokenURI = newURI;
        emit BaseURIUpdated(oldURI, newURI);
    }

    /// @notice Switch the payment currency for future mints. To prevent
    ///         buyers from accidentally paying in an unexpected token mid-
    ///         drop, this is only allowed before the first mint has
    ///         settled (i.e. `currentSupply == 0`).
    function setMintingCurrency(address newCurrency) external onlyOwner {
        if (currentSupply != 0) revert InvalidParameters();
        address oldCurrency = mintingCurrency;
        mintingCurrency = newCurrency;
        emit MintingCurrencyUpdated(oldCurrency, newCurrency);
    }

    function setCreatorFeeBps(uint96 newFeeBps) external onlyOwner {
        if (newFeeBps > 1000) revert InvalidCreatorFeeBps();
        uint96 oldFeeBps = creatorFeeBps;
        creatorFeeBps = newFeeBps;

        _setDefaultRoyalty(owner(), newFeeBps);

        emit CreatorFeeUpdated(oldFeeBps, newFeeBps);
    }

    function setMintStartTime(uint256 newStartTime) external onlyOwner {
        uint256 oldStartTime = mintStartTime;
        mintStartTime = newStartTime;
        emit MintStartTimeUpdated(oldStartTime, newStartTime);
    }

    // -----------------------------------------------------------------
    // Internal payment + mint loop (shared by mint / allowlistMint)
    // -----------------------------------------------------------------

    // Recipients here are fixed and trusted: `platformTreasury` (set at
    // construction) and `owner()` (the collection creator). Neither is
    // attacker-controlled, so the arbitrary-send-eth detector is a false
    // positive.
    // slither-disable-next-line arbitrary-send-eth
    function _settlePayment(uint256 totalCost) internal {
        if (mintingCurrency == address(0)) {
            if (msg.value != totalCost) revert InsufficientPayment();
        } else {
            if (msg.value > 0) revert InvalidParameters();
            IERC20(mintingCurrency).safeTransferFrom(msg.sender, address(this), totalCost);
        }

        uint256 platformFee = (totalCost * platformFeeBps) / 10000;
        uint256 remainingAmount = totalCost - platformFee;

        if (mintingCurrency == address(0)) {
            (bool platformSuccess, ) = platformTreasury.call{value: platformFee}("");
            if (!platformSuccess) revert TransferFailed();

            (bool remainingSuccess, ) = owner().call{value: remainingAmount}("");
            if (!remainingSuccess) revert TransferFailed();
        } else {
            IERC20(mintingCurrency).safeTransfer(platformTreasury, platformFee);
            IERC20(mintingCurrency).safeTransfer(owner(), remainingAmount);
        }
    }

    function _mintBatch(address to, uint256 quantity, uint256 unitPrice) internal {
        // currentSupply is incremented BEFORE _safeMint so that any
        // onERC721Received callback that reads tokenURI(tokenId) on the
        // just-minted token doesn't revert against the strict
        // `tokenId > currentSupply` check.
        uint256 startTokenId = currentSupply + 1;
        for (uint256 i = 0; i < quantity; i++) {
            uint256 tokenId = startTokenId + i;
            currentSupply = tokenId;
            _safeMint(to, tokenId);
            emit TokenMinted(to, tokenId, unitPrice);
        }
    }

    // -----------------------------------------------------------------
    // ERC-721 / Enumerable / 2981 plumbing
    // -----------------------------------------------------------------

    // encode-packed-collision is a false positive: the third argument
    // ".json" is a fixed literal with a leading non-digit, so no
    // (baseTokenURI, tokenId) pair can ever produce ambiguous packed
    // bytes shared with another (baseTokenURI', tokenId') pair.
    // slither-disable-next-line encode-packed-collision
    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, IArtvybeCollection)
        returns (string memory)
    {
        if (tokenId == 0 || tokenId > currentSupply) revert InvalidTokenId();

        if (bytes(baseTokenURI).length == 0) {
            return "";
        }

        return string(abi.encodePacked(baseTokenURI, _toString(tokenId), ".json"));
    }

    function _update(address to, uint256 tokenId, address auth)
        internal
        virtual
        override(ERC721, ERC721Enumerable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value)
        internal
        virtual
        override(ERC721, ERC721Enumerable)
    {
        super._increaseBalance(account, value);
    }

    function tokenOfOwnerByIndex(address ownerAddr, uint256 index)
        public
        view
        override(ERC721Enumerable)
        returns (uint256)
    {
        return super.tokenOfOwnerByIndex(ownerAddr, index);
    }

    function totalSupply() public view override(ERC721Enumerable) returns (uint256) {
        return currentSupply;
    }

    function tokenByIndex(uint256 index)
        public
        view
        override(ERC721Enumerable)
        returns (uint256)
    {
        return super.tokenByIndex(index);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable, ERC2981)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    // -----------------------------------------------------------------
    // Emergency recovery
    // -----------------------------------------------------------------

    function recoverTokens(address token, address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();

        uint256 contractBalance = IERC20(token).balanceOf(address(this));
        if (amount > contractBalance) revert InsufficientBalance();

        IERC20(token).safeTransfer(to, amount);
    }

    // contractBalance == 0 is intentional: revert when there's nothing to
    // sweep so the owner doesn't waste gas on a no-op.
    // slither-disable-next-line incorrect-equality
    function recoverNativeTokens(address to) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();

        uint256 contractBalance = address(this).balance;
        if (contractBalance == 0) revert InsufficientBalance();

        (bool success, ) = to.call{value: contractBalance}("");
        if (!success) revert TransferFailed();
    }

    receive() external payable {}
}
