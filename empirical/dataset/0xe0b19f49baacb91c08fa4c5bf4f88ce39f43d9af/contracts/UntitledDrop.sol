// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

interface IDelegateRegistry {
    function checkDelegateForAll(address to, address from, bytes32 rights) external view returns (bool);
}

interface ICreatorToken {
    event TransferValidatorUpdated(address oldValidator, address newValidator);

    function getTransferValidator() external view returns (address validator);
    function setTransferValidator(address validator) external;
    function getTransferValidationFunction() external view returns (bytes4 functionSignature, bool isViewFunction);
}

interface ITransferValidator {
    function validateTransfer(address caller, address from, address to, uint256 tokenId) external view;
}

interface ITransferValidatorSetTokenType {
    function setTokenTypeOfCollection(address collection, uint16 tokenType) external;
}

/**
 * @title UntitledDrop
 * @notice ERC-721 mint contract for a tiny allowlist and public test drop.
 */
contract UntitledDrop is ERC721, ERC2981, Ownable2Step, Pausable, ReentrancyGuard, ICreatorToken {
    using Strings for uint256;

    uint256 public constant MAX_SUPPLY = 2;
    uint256 public constant PUBLIC_PRICE = 0.003 ether;
    uint256 public constant MINT_WINDOW_DURATION = 24 hours;
    uint96 public constant MAX_ROYALTY_BPS = 1000;
    bytes32 public constant DELEGATE_RIGHTS = bytes32(0);
    address public constant DEFAULT_TRANSFER_VALIDATOR = 0x721C008fdff27BF06E7E123956E2Fe03B63342e3;
    uint16 private constant TOKEN_TYPE_ERC721 = 721;

    uint256 public totalMinted;
    uint256 public opensAt;
    uint256 public closesAt;
    uint256 public finalSupply;

    bool public supplyLocked;
    bool public revealed;
    bool public metadataLocked;

    bytes32 public allowlistMerkleRoot;
    address public delegateRegistry;
    address payable public treasury;

    string private _baseTokenURI;
    string private _placeholderURI;
    address private _transferValidator;
    bool private _transferValidatorInitialized;

    mapping(address => bool) public hasMinted;
    mapping(uint256 => uint256) public tokenSeed;

    event MintWindowSet(uint256 opensAt, uint256 closesAt);
    event AllowlistMerkleRootUpdated(bytes32 oldRoot, bytes32 newRoot);
    event DelegateRegistryUpdated(address indexed oldRegistry, address indexed newRegistry);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event Minted(address indexed account, address indexed operator, uint256 indexed tokenId, uint256 pricePaid, uint256 seed);
    event SupplyLocked(uint256 finalSupply);
    event Revealed(string baseURI);
    event PlaceholderURIUpdated(string placeholderURI);
    event MetadataLocked();
    event Withdrawn(address indexed to, uint256 amount);

    error AlreadyMinted(address account);
    error DelegateNotAuthorized(address account, address operator);
    error IncorrectPayment(uint256 expected, uint256 received);
    error InvalidProof(address account);
    error InvalidTokenId(uint256 tokenId);
    error InvalidWindow();
    error MetadataIsLocked();
    error MintClosed();
    error MintNotOpen();
    error MintStillOpen();
    error NothingToWithdraw();
    error RoyaltyTooHigh();
    error SupplyExhausted();
    error InvalidTransferValidator();
    error WindowAlreadyOpen();
    error WithdrawAmountExceedsBalance();
    error WithdrawFailed();
    error ZeroAddress();
    error NotRevealed();
    error OwnershipCannotBeRenounced();

    constructor(
        address payable treasury_,
        address royaltyReceiver_,
        uint96 royaltyBps_,
        string memory placeholderURI_,
        bytes32 allowlistMerkleRoot_,
        address delegateRegistry_
    ) ERC721("Untitled", "UNTLD") Ownable(msg.sender) {
        if (treasury_ == address(0) || royaltyReceiver_ == address(0)) revert ZeroAddress();
        if (royaltyBps_ > MAX_ROYALTY_BPS) revert RoyaltyTooHigh();

        treasury = treasury_;
        _placeholderURI = placeholderURI_;
        allowlistMerkleRoot = allowlistMerkleRoot_;
        delegateRegistry = delegateRegistry_;
        _setDefaultRoyalty(royaltyReceiver_, royaltyBps_);
        emit TransferValidatorUpdated(address(0), DEFAULT_TRANSFER_VALIDATOR);
        _registerTokenType(DEFAULT_TRANSFER_VALIDATOR);
    }

    receive() external payable {
        revert IncorrectPayment(0, msg.value);
    }

    function mint(bytes32[] calldata allowlistProof) external payable whenNotPaused nonReentrant returns (uint256 tokenId) {
        return _mintFor(msg.sender, allowlistProof);
    }

    function mintFor(address account, bytes32[] calldata allowlistProof)
        external
        payable
        whenNotPaused
        nonReentrant
        returns (uint256 tokenId)
    {
        _requireAuthorizedOperator(account, msg.sender);
        return _mintFor(account, allowlistProof);
    }

    function priceFor(address account, bytes32[] calldata allowlistProof) public view returns (uint256) {
        return isAllowlisted(account, allowlistProof) ? 0 : PUBLIC_PRICE;
    }

    function isAllowlisted(address account, bytes32[] calldata allowlistProof) public view returns (bool) {
        if (allowlistMerkleRoot == bytes32(0)) return false;
        bytes32 leaf = _allowlistLeaf(account);
        return MerkleProof.verifyCalldata(allowlistProof, allowlistMerkleRoot, leaf);
    }

    function remaining() external view returns (uint256) {
        if (block.timestamp >= closesAt && closesAt != 0) return 0;
        uint256 cap = supplyLocked ? finalSupply : MAX_SUPPLY;
        if (totalMinted >= cap) return 0;
        return cap - totalMinted;
    }

    function currentSupplyCap() external view returns (uint256) {
        return supplyLocked ? finalSupply : MAX_SUPPLY;
    }

    function getTokenSeed(uint256 tokenId) external view returns (uint256) {
        if (tokenId == 0 || tokenId > totalMinted) revert InvalidTokenId(tokenId);
        return tokenSeed[tokenId];
    }

    function setMintWindow(uint256 opensAt_) external onlyOwner {
        if (opensAt != 0 && block.timestamp >= opensAt) revert WindowAlreadyOpen();
        if (opensAt_ < block.timestamp) revert InvalidWindow();
        opensAt = opensAt_;
        closesAt = opensAt_ + MINT_WINDOW_DURATION;
        emit MintWindowSet(opensAt, closesAt);
    }

    function setAllowlistMerkleRoot(bytes32 newRoot) external onlyOwner {
        if (opensAt != 0 && block.timestamp >= opensAt) revert WindowAlreadyOpen();
        bytes32 oldRoot = allowlistMerkleRoot;
        allowlistMerkleRoot = newRoot;
        emit AllowlistMerkleRootUpdated(oldRoot, newRoot);
    }

    function setDelegateRegistry(address newDelegateRegistry) external onlyOwner {
        address oldDelegateRegistry = delegateRegistry;
        delegateRegistry = newDelegateRegistry;
        emit DelegateRegistryUpdated(oldDelegateRegistry, newDelegateRegistry);
    }

    function setTreasury(address payable newTreasury) external onlyOwner {
        if (newTreasury == address(0)) revert ZeroAddress();
        address oldTreasury = treasury;
        treasury = newTreasury;
        emit TreasuryUpdated(oldTreasury, newTreasury);
    }

    function setDefaultRoyalty(address receiver, uint96 feeNumerator) external onlyOwner {
        if (receiver == address(0)) revert ZeroAddress();
        if (feeNumerator > MAX_ROYALTY_BPS) revert RoyaltyTooHigh();
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    function getTransferValidator() public view returns (address validator) {
        validator = _transferValidator;
        if (validator == address(0) && !_transferValidatorInitialized) {
            validator = DEFAULT_TRANSFER_VALIDATOR;
        }
    }

    function setTransferValidator(address validator) external onlyOwner {
        if (validator != address(0) && validator.code.length == 0) revert InvalidTransferValidator();
        address oldValidator = getTransferValidator();
        _transferValidatorInitialized = true;
        _transferValidator = validator;
        emit TransferValidatorUpdated(oldValidator, validator);
        _registerTokenType(validator);
    }

    function getTransferValidationFunction() external pure returns (bytes4 functionSignature, bool isViewFunction) {
        return (bytes4(keccak256("validateTransfer(address,address,address,uint256)")), true);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function lockSupply() public {
        if (closesAt == 0 || block.timestamp < closesAt) revert MintStillOpen();
        _lockSupply(totalMinted);
    }

    function reveal(string calldata baseURI_) external onlyOwner {
        if (metadataLocked) revert MetadataIsLocked();
        _baseTokenURI = baseURI_;
        revealed = true;
        emit Revealed(baseURI_);
    }

    function setBaseURI(string calldata baseURI_) external onlyOwner {
        if (metadataLocked) revert MetadataIsLocked();
        _baseTokenURI = baseURI_;
    }

    function setPlaceholderURI(string calldata placeholderURI_) external onlyOwner {
        if (metadataLocked) revert MetadataIsLocked();
        _placeholderURI = placeholderURI_;
        emit PlaceholderURIUpdated(placeholderURI_);
    }

    function lockMetadata() external onlyOwner {
        if (!revealed) revert NotRevealed();
        metadataLocked = true;
        emit MetadataLocked();
    }

    function withdraw(address payable to) external onlyOwner nonReentrant {
        uint256 bal = address(this).balance;
        if (bal == 0) revert NothingToWithdraw();
        _sendValue(to, bal);
    }

    function withdrawAmount(address payable to, uint256 amount) external onlyOwner nonReentrant {
        if (amount == 0) revert NothingToWithdraw();
        if (amount > address(this).balance) revert WithdrawAmountExceedsBalance();
        _sendValue(to, amount);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        if (!revealed) return _placeholderURI;
        return string(abi.encodePacked(_baseTokenURI, tokenId.toString(), ".json"));
    }

    function renounceOwnership() public view override onlyOwner {
        revert OwnershipCannotBeRenounced();
    }

    function _mintFor(address account, bytes32[] calldata allowlistProof) internal returns (uint256 tokenId) {
        if (account == address(0)) revert ZeroAddress();
        if (opensAt == 0 || block.timestamp < opensAt) revert MintNotOpen();
        if (block.timestamp >= closesAt) revert MintClosed();
        if (hasMinted[account]) revert AlreadyMinted(account);
        if (totalMinted >= MAX_SUPPLY) revert SupplyExhausted();

        uint256 expectedPrice = priceFor(account, allowlistProof);
        if (msg.value != expectedPrice) revert IncorrectPayment(expectedPrice, msg.value);

        tokenId = totalMinted + 1;
        totalMinted = tokenId;
        hasMinted[account] = true;

        uint256 seed = uint256(
            keccak256(abi.encodePacked(account, msg.sender, msg.value, blockhash(block.number - 1), tokenId))
        );
        tokenSeed[tokenId] = seed;

        _safeMint(account, tokenId);
        emit Minted(account, msg.sender, tokenId, msg.value, seed);

        if (totalMinted == MAX_SUPPLY) {
            _lockSupply(MAX_SUPPLY);
        }
    }

    function _requireAuthorizedOperator(address account, address operator) internal view {
        if (!_isAuthorizedOperator(account, operator)) revert DelegateNotAuthorized(account, operator);
    }

    function _isAuthorizedOperator(address account, address operator) internal view returns (bool) {
        if (account == operator) return true;
        address registry = delegateRegistry;
        if (registry == address(0)) return false;
        try IDelegateRegistry(registry).checkDelegateForAll(operator, account, DELEGATE_RIGHTS) returns (bool valid) {
            return valid;
        } catch {
            return false;
        }
    }

    function _allowlistLeaf(address account) internal pure returns (bytes32) {
        return keccak256(abi.encode(account));
    }

    function _lockSupply(uint256 supply) internal {
        if (supplyLocked) return;
        supplyLocked = true;
        finalSupply = supply;
        emit SupplyLocked(supply);
    }

    function _sendValue(address payable to, uint256 amount) internal {
        if (to == address(0)) revert ZeroAddress();
        (bool ok, ) = to.call{value: amount}("");
        if (!ok) revert WithdrawFailed();
        emit Withdrawn(to, amount);
    }

    function _registerTokenType(address validator) internal {
        if (validator == address(0) || validator.code.length == 0) return;
        try ITransferValidatorSetTokenType(validator).setTokenTypeOfCollection(address(this), TOKEN_TYPE_ERC721) {
        } catch {
        }
    }

    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);
        address validator = getTransferValidator();

        if (from != address(0) && to != address(0) && validator != address(0) && validator.code.length > 0) {
            if (_msgSender() != validator) {
                ITransferValidator(validator).validateTransfer(auth, from, to, tokenId);
            }
        }

        return super._update(to, tokenId, auth);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC2981)
        returns (bool)
    {
        return interfaceId == type(ICreatorToken).interfaceId || super.supportsInterface(interfaceId);
    }
}
