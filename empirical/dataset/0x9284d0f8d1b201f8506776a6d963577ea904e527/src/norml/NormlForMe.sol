// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "../interfaces/IERC20.sol";
import {SimpleERC721} from "../token/SimpleERC721.sol";
import {Base64} from "../utils/Base64.sol";

/// @notice NormlAssets companion contract — generates the on-chain animation HTML
///         for a given ForMe token id. When set on NormlForMe, the fallback tokenURI
///         embeds the returned data URI as `animation_url` so secondary marketplaces
///         show the correct visual without any off-chain trickery.
interface INormlAssets {
    function animationURIForMe(uint256 tokenId) external view returns (string memory);
    function CANVAS_W(uint256 artworkId) external view returns (uint16);
    function CANVAS_H(uint256 artworkId) external view returns (uint16);
    function getTokenChunks(uint256 artworkId) external view returns (address[] memory);
}

/// @notice Optional external renderer. When set on `NormlForMe`, the NFT's
///         `tokenURI` delegates to this contract so external indexers
///         (OpenSea, rare.xyz, …) get a full animation_url + image. When
///         unset, `NormlForMe` falls back to a self-contained JSON with the
///         locked amount and hash as attributes.
interface INormlForMeRenderer {
    function tokenURI(uint256 tokenId, uint256 lockedAmount, bytes32 hash)
        external
        view
        returns (string memory);
}

/// @title  NormlForMe ("Normal 4 Me")
/// @notice ERC-721 collection where each NFT permanently associates a chunk
///         of NORML tokens with a user-supplied determinism hash. NORML is
///         escrowed inside this contract; the NFT owner can always add more,
///         and burning the NFT returns the full locked amount to the current
///         owner. Mint price is fixed (`MINT_PRICE`) and minting opens when
///         the owner calls `setMintActive(true)`, which starts a 24-hour
///         open-edition window (`mintEndsAt`). `mintActive` is false by default.
///
///         Ecosystem hooks:
///           - ERC-2981 royalties on every secondary sale (default 10%).
///           - Optional primary-mint fee split: owner can route a slice of
///             `msg.value` to a third party (e.g. SuperRare) at mint time
///             via `setSuperrareFee(receiver, bps)`. Off by default.
///           - Router-trusted `*For(user, …)` entry points so a Router
///             contract can act on behalf of the user with a single approval.
///
/// @dev    Drop-in replacement for the legacy stake-bucket `NormlForMe`. The
///         old `getStake/stake/unstake/addToStake/updateDeterminismHash`
///         surface is gone; new dependents use `lockedAmount(id)` and
///         `determinismHash(id)` instead.
///
/// @author jiwa
contract NormlForMe is SimpleERC721 {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    uint256 public constant MINT_PRICE_DEFAULT = 0.02 ether;

    /// @notice 24-hour open-edition mint window length (used as default at deploy).
    uint256 public constant MINT_WINDOW = 24 hours;

    /// @notice Max basis points any settable royalty/fee can take. 25%.
    uint256 public constant MAX_FEE_BPS = 2_500;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.•°.•°:°.´+˚.*°.˚:*.´+°.•°:´*.´•*.•°.•*/

    address public immutable NORML_TOKEN;

    /// @notice Per-mint ETH price. Settable by owner.
    uint256 public mintPrice = MINT_PRICE_DEFAULT;

    /// @notice Whether minting is currently active. False by default; owner
    ///         calls `setMintActive(true)` to open the 24-hour window.
    bool public mintActive;

    /// @notice Unix timestamp at which the open-edition mint window closes.
    ///         Set automatically when `setMintActive(true)` is first called;
    ///         settable by owner thereafter via `setMintEndsAt`.
    uint256 public mintEndsAt;

    /// @notice Hard cap on the total number of NFTs that can be minted.
    ///         `0` means uncapped. Settable by owner.
    uint256 public maxMint;

    /// @notice Hard cap on the NORML amount locked in any single NFT (base 1e18).
    ///         `0` means uncapped. Enforced on both initial mint and `addTokens`.
    ///         Settable by owner.
    uint256 public maxLockedTokens;

    /// @notice Locked NORML amount per token (base 1e18 units).
    mapping(uint256 tokenId => uint256 amount) public lockedAmount;

    /// @notice User-supplied determinism hash per token.
    mapping(uint256 tokenId => bytes32 hash) public determinismHash;

    /// @notice Total minted so far (monotonic; not decremented on burn).
    uint256 public totalMinted;

    /// @notice Number of NFTs currently in circulation (decremented on burn).
    uint256 public totalSupply;

    /// @notice NormlAssets contract. When set, the fallback `tokenURI` calls
    ///         `animationURIForMe(tokenId)` and embeds the result as `animation_url`
    ///         so secondary marketplaces (OpenSea, rare.xyz, …) display the correct
    ///         deterministic artwork without any off-chain intervention.
    address public normlAssets;

    /// @notice Optional external metadata renderer. When zero, `tokenURI`
    ///         returns a self-contained JSON.
    address public renderer;

    /// @notice Trusted router (single-approval UX). Settable by owner; gated
    ///         entry points: `mintFor`, `addTokensFor`, `burnAndUnlockFor`.
    address public router;

    /// @notice ERC-2981 royalty receiver (collection-wide).
    address public royaltyReceiver;

    /// @notice ERC-2981 royalty in basis points (default 10%).
    uint256 public royaltyBps = 1_000;

    /// @notice Optional primary-mint fee receiver (e.g. SuperRare protocol).
    address public superrareFeeReceiver;

    /// @notice Optional primary-mint fee in bps of `MINT_PRICE`. Off by default.
    uint256 public superrareFeeBps;

    string public collectionDescription;
    string public externalUrl;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.•°.•°:°.´+˚.*°.˚:*.´+°.•°:´*.´•*.•°.•*/

    event Minted(address indexed to, uint256 indexed tokenId, uint256 amount, bytes32 hash);
    event TokensAdded(uint256 indexed tokenId, address indexed from, uint256 amount, uint256 newTotal);
    event BurnedAndUnlocked(uint256 indexed tokenId, address indexed to, uint256 amount);
    event Withdrawn(address indexed to, uint256 amount);
    event NormlAssetsUpdated(address indexed previousAssets, address indexed newAssets);
    event RendererUpdated(address indexed previousRenderer, address indexed newRenderer);
    event RouterUpdated(address indexed previousRouter, address indexed newRouter);
    event RoyaltyUpdated(address indexed receiver, uint256 bps);
    event SuperrareFeeUpdated(address indexed receiver, uint256 bps);
    event SuperrareFeePaid(address indexed receiver, uint256 amount, uint256 tokenId);
    event MintPriceUpdated(uint256 previousPrice, uint256 newPrice);
    event MintActiveUpdated(bool active);
    event MintEndsAtUpdated(uint256 previousEndsAt, uint256 newEndsAt);
    event MaxMintUpdated(uint256 previousMaxMint, uint256 newMaxMint);
    event MaxLockedTokensUpdated(uint256 previousMax, uint256 newMax);
    event MetadataUpdate(uint256 _tokenId); // ERC-4906
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId); // ERC-4906

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           ERRORS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error InvalidNormlToken();
    error MintClosed();
    error InsufficientPayment();
    error ZeroAmount();
    error TransferFailed();
    error NotTokenOwner();
    error EthTransferFailed();
    error InvalidRecipient();
    error NotRouter();
    error FeeTooHigh();
    error MaxMintReached();
    error MaxLockedTokensExceeded();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         MODIFIERS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    modifier onlyRouter() {
        if (msg.sender != router || router == address(0)) revert NotRouter();
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CONSTRUCTOR                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    constructor(
        address normlToken,
        string memory name_,
        string memory symbol_,
        string memory description_,
        string memory externalUrl_
    ) SimpleERC721(name_, symbol_) {
        if (normlToken == address(0)) revert InvalidNormlToken();
        NORML_TOKEN = normlToken;
        maxMint = 200;
        collectionDescription = description_;
        externalUrl = externalUrl_;
        // Default royalty receiver = deployer; owner can re-point later.
        royaltyReceiver = msg.sender;
        emit RoyaltyUpdated(msg.sender, royaltyBps);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          MINTING                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.•°.•°:°.´+˚.*°.˚:*.´+°.•°:´*.´•*.•°.•*/

    /// @notice Mint a Normal 4 Me NFT locking `amount` NORML tokens.
    /// @dev    Caller must `approve(this, amount)` on the NORML token first.
    ///         `msg.value` must equal exactly `MINT_PRICE`. Locked NORML lives
    ///         inside this contract until `burnAndUnlock`. The determinism
    ///         hash is generated on-chain from block.prevrandao + tokenId +
    ///         recipient (see `_mint`).
    function mint(uint256 amount) external payable returns (uint256 tokenId) {
        return _mint(msg.sender, msg.sender, amount);
    }

    /// @notice Owner-only mint that bypasses the mintActive / mintEndsAt
    ///         window. Useful for testing and pre-launch setup. The owner
    ///         must still supply `mintPrice` ETH and have approved this
    ///         contract for `amount` NORML tokens.
    function ownerMint(address recipient, uint256 amount)
        external
        payable
        onlyOwner
        returns (uint256 tokenId)
    {
        if (msg.value != mintPrice) revert InsufficientPayment();
        if (amount == 0) revert ZeroAmount();
        uint256 capMint = maxMint;
        if (capMint != 0 && totalMinted >= capMint) revert MaxMintReached();
        uint256 capLocked = maxLockedTokens;
        if (capLocked != 0 && amount > capLocked) revert MaxLockedTokensExceeded();

        bool ok = IERC20(NORML_TOKEN).transferFrom(msg.sender, address(this), amount);
        if (!ok) revert TransferFailed();

        tokenId = totalMinted;
        unchecked {
            totalMinted = tokenId + 1;
            totalSupply += 1;
        }

        bytes32 hash = keccak256(abi.encodePacked(block.prevrandao, tokenId, recipient));
        lockedAmount[tokenId] = amount;
        determinismHash[tokenId] = hash;

        _safeMint(recipient, tokenId);

        emit Minted(recipient, tokenId, amount, hash);
    }

    /// @notice Router-trusted mint. Credits `user`, pulls NORML from
    ///         `msg.sender` (the router, which has already pulled from user).
    function mintFor(address user, uint256 amount)
        external
        payable
        onlyRouter
        returns (uint256 tokenId)
    {
        return _mint(user, msg.sender, amount);
    }

    function _mint(address recipient, address payer, uint256 amount)
        internal
        returns (uint256 tokenId)
    {
        if (msg.value != mintPrice) revert InsufficientPayment();
        if (amount == 0) revert ZeroAmount();
        if (!mintActive || block.timestamp > mintEndsAt) revert MintClosed();
        uint256 capMint = maxMint;
        if (capMint != 0 && totalMinted >= capMint) revert MaxMintReached();
        uint256 capLocked = maxLockedTokens;
        if (capLocked != 0 && amount > capLocked) revert MaxLockedTokensExceeded();

        bool ok = IERC20(NORML_TOKEN).transferFrom(payer, address(this), amount);
        if (!ok) revert TransferFailed();

        tokenId = totalMinted;
        unchecked {
            totalMinted = tokenId + 1;
            totalSupply += 1;
        }

        bytes32 hash = keccak256(abi.encodePacked(block.prevrandao, tokenId, recipient));
        lockedAmount[tokenId] = amount;
        determinismHash[tokenId] = hash;

        _safeMint(recipient, tokenId);

        // Optional SuperRare primary-fee split. Off unless owner configures it.
        uint256 feeBps = superrareFeeBps;
        address feeTo = superrareFeeReceiver;
        if (feeBps > 0 && feeTo != address(0)) {
            uint256 fee = (msg.value * feeBps) / 10_000;
            if (fee > 0) {
                (bool feeOk, ) = feeTo.call{value: fee}("");
                if (!feeOk) revert EthTransferFailed();
                emit SuperrareFeePaid(feeTo, fee, tokenId);
            }
        }

        emit Minted(recipient, tokenId, amount, hash);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       TOKEN OPERATIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.•°.•°:°.´+˚.*°.˚:*.´+°.•°:´*.´•*.•°.•*/

    /// @notice Add more NORML tokens to an existing NFT. NFT owner only.
    /// @dev    Caller must `approve(this, amount)` on the NORML token first.
    function addTokens(uint256 tokenId, uint256 amount) external {
        _addTokens(msg.sender, msg.sender, tokenId, amount);
    }

    /// @notice Router-trusted addTokens. `user` must be the NFT owner.
    function addTokensFor(address user, uint256 tokenId, uint256 amount) external onlyRouter {
        _addTokens(user, msg.sender, tokenId, amount);
    }

    function _addTokens(address user, address payer, uint256 tokenId, uint256 amount) internal {
        if (ownerOf(tokenId) != user) revert NotTokenOwner();
        if (amount == 0) revert ZeroAmount();

        bool ok = IERC20(NORML_TOKEN).transferFrom(payer, address(this), amount);
        if (!ok) revert TransferFailed();

        uint256 newTotal = lockedAmount[tokenId] + amount;
        uint256 capLocked = maxLockedTokens;
        if (capLocked != 0 && newTotal > capLocked) revert MaxLockedTokensExceeded();
        lockedAmount[tokenId] = newTotal;

        emit TokensAdded(tokenId, user, amount, newTotal);
        emit MetadataUpdate(tokenId);
    }

    /// @notice Burn the NFT and unlock all NORML tokens to the current owner.
    function burnAndUnlock(uint256 tokenId) external {
        _burnAndUnlock(msg.sender, tokenId);
    }

    /// @notice Router-trusted burn. `user` must be the NFT owner.
    function burnAndUnlockFor(address user, uint256 tokenId) external onlyRouter {
        _burnAndUnlock(user, tokenId);
    }

    function _burnAndUnlock(address user, uint256 tokenId) internal {
        address tokenOwner = ownerOf(tokenId);
        if (tokenOwner != user) revert NotTokenOwner();

        uint256 amount = lockedAmount[tokenId];

        // Effects: clear storage and burn before external transfer.
        delete lockedAmount[tokenId];
        delete determinismHash[tokenId];
        _burn(tokenId);
        unchecked { totalSupply -= 1; }

        if (amount > 0) {
            bool ok = IERC20(NORML_TOKEN).transfer(tokenOwner, amount);
            if (!ok) revert TransferFailed();
        }

        emit BurnedAndUnlocked(tokenId, tokenOwner, amount);
    }

    /// @dev Internal burn — SimpleERC721 does not expose one, so we mirror its
    ///      storage layout. Clears approvals + ownership + balance.
    function _burn(uint256 tokenId) internal {
        address tokenOwner = _ownerOf[tokenId];
        if (tokenOwner == address(0)) revert ERC721NonexistentToken(tokenId);
        delete _tokenApprovals[tokenId];
        unchecked { _balanceOf[tokenOwner] -= 1; }
        delete _ownerOf[tokenId];
        emit Transfer(tokenOwner, address(0), tokenId);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                            ADMIN                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.•°.•°:°.´+˚.*°.˚:*.´+°.•°:´*.´•*.•°.•*/

    /// @notice Set or replace the trusted router. `address(0)` disables.
    function setRouter(address newRouter) external onlyOwner {
        emit RouterUpdated(router, newRouter);
        router = newRouter;
    }

    /// @notice Open or close the mint. Calling with `true` starts (or restarts)
    ///         a fresh 24-hour window; `false` pauses minting immediately.
    ///         Only starts the window if transitioning from inactive → active
    ///         (or if the previous window has already expired), so calling
    ///         `setMintActive(true)` again mid-window does NOT reset the clock.
    function setMintActive(bool newActive) external onlyOwner {
        if (newActive && (!mintActive || block.timestamp > mintEndsAt)) {
            uint256 newEndsAt = block.timestamp + MINT_WINDOW;
            emit MintEndsAtUpdated(mintEndsAt, newEndsAt);
            mintEndsAt = newEndsAt;
        }
        mintActive = newActive;
        emit MintActiveUpdated(newActive);
    }

    /// @notice Update the per-mint ETH price. Applies to subsequent mints only.
    function setMintPrice(uint256 newPrice) external onlyOwner {
        emit MintPriceUpdated(mintPrice, newPrice);
        mintPrice = newPrice;
    }

    /// @notice Update the open-edition close timestamp. Can extend (re-open)
    ///         or shorten the window. Pass `0` to close minting immediately.
    function setMintEndsAt(uint256 newEndsAt) external onlyOwner {
        emit MintEndsAtUpdated(mintEndsAt, newEndsAt);
        mintEndsAt = newEndsAt;
    }

    /// @notice Cap on total NFTs that can ever be minted. `0` removes the cap.
    ///         The cap may not be set below the current `totalMinted`.
    function setMaxMint(uint256 newMax) external onlyOwner {
        if (newMax != 0 && newMax < totalMinted) revert MaxMintReached();
        emit MaxMintUpdated(maxMint, newMax);
        maxMint = newMax;
    }

    /// @notice Cap on NORML locked in any single NFT (base 1e18). `0` removes
    ///         the cap. Existing balances above the new cap are grandfathered;
    ///         only future mints / `addTokens` calls are checked.
    function setMaxLockedTokens(uint256 newMax) external onlyOwner {
        emit MaxLockedTokensUpdated(maxLockedTokens, newMax);
        maxLockedTokens = newMax;
    }

    /// @notice Set or replace the NormlAssets contract address.
    function setNormlAssets(address newAssets) external onlyOwner {
        emit NormlAssetsUpdated(normlAssets, newAssets);
        normlAssets = newAssets;
        if (totalMinted > 0) emit BatchMetadataUpdate(0, totalMinted - 1);
    }

    /// @notice Set or replace the external metadata renderer.
    function setRenderer(address newRenderer) external onlyOwner {
        emit RendererUpdated(renderer, newRenderer);
        renderer = newRenderer;
        if (totalMinted > 0) emit BatchMetadataUpdate(0, totalMinted - 1);
    }

    /// @notice Configure ERC-2981 royalty. `bps` capped at `MAX_FEE_BPS`.
    function setRoyalty(address receiver, uint256 bps) external onlyOwner {
        if (bps > MAX_FEE_BPS) revert FeeTooHigh();
        royaltyReceiver = receiver;
        royaltyBps = bps;
        emit RoyaltyUpdated(receiver, bps);
    }

    /// @notice Configure optional SuperRare primary-mint fee. Zero `bps` or
    ///         zero `receiver` disables. Capped at `MAX_FEE_BPS`.
    function setSuperrareFee(address receiver, uint256 bps) external onlyOwner {
        if (bps > MAX_FEE_BPS) revert FeeTooHigh();
        superrareFeeReceiver = receiver;
        superrareFeeBps = bps;
        emit SuperrareFeeUpdated(receiver, bps);
    }

    /// @notice Withdraw accumulated ETH (mint proceeds) to `to`.
    function withdraw(address payable to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert InvalidRecipient();
        if (amount == 0 || amount > address(this).balance) revert ZeroAmount();
        (bool ok, ) = to.call{value: amount}("");
        if (!ok) revert EthTransferFailed();
        emit Withdrawn(to, amount);
    }

    /// @notice Sweep the full ETH balance to `to`.
    function withdrawAll(address payable to) external onlyOwner {
        if (to == address(0)) revert InvalidRecipient();
        uint256 bal = address(this).balance;
        if (bal == 0) revert ZeroAmount();
        (bool ok, ) = to.call{value: bal}("");
        if (!ok) revert EthTransferFailed();
        emit Withdrawn(to, bal);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          METADATA                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.•°.•°:°.´+˚.*°.˚:*.´+°.•°:´*.´•*.•°.•*/

    /// @notice ERC-721 metadata URI. Delegates to `renderer` when set,
    ///         otherwise returns a self-contained base64 data URI.
    function tokenURI(uint256 tokenId) external view returns (string memory) {
        _requireOwned(tokenId);
        address r = renderer;
        if (r != address(0)) {
            return INormlForMeRenderer(r).tokenURI(
                tokenId,
                lockedAmount[tokenId],
                determinismHash[tokenId]
            );
        }
        return _fallbackTokenURI(tokenId);
    }

    function _fallbackTokenURI(uint256 tokenId) internal view returns (string memory) {
        uint256 amt = lockedAmount[tokenId];
        bytes32 h = determinismHash[tokenId];
        string memory hashHex = _bytes32ToHex(h);

        // Build animation_url AND image by delegating to NormlAssets when wired.
        // - animation_url: data:text/html;base64,... live shader for marketplace previews.
        // - image:         data:image/svg+xml;base64,... static thumbnail (cropped webp
        //                  honoring this token's hash position + stake size, with N4M.###
        //                  + pixel-count overlay matching the on-chain shader window).
        address assets = normlAssets;
        string memory animUrl;
        string memory imgUrl;
        if (assets != address(0)) {
            animUrl = INormlAssets(assets).animationURIForMe(tokenId);
            imgUrl  = _imageURIForMe(assets, tokenId, amt, h);
        }

        // Emit JSON as `data:application/json;utf8,` so the embedded data URIs
        // (each itself base64) don't need a second outer base64 pass — saves
        // a large allocation per tokenURI fetch. OpenSea / SuperRare / rare.xyz
        // all accept utf8 JSON data URIs.
        if (bytes(animUrl).length > 0) {
            return string.concat(
                'data:application/json;utf8,{"name":"', name, ' #', _toString(tokenId), '"',
                ',"description":"', collectionDescription, '"',
                ',"external_url":"', externalUrl, '"',
                ',"image":"', imgUrl, '"',
                ',"animation_url":"', animUrl, '"',
                ',"attributes":[',
                    '{"trait_type":"Locked NORML (pixels)","value":', _toString(amt / 1e18), '},',
                    '{"trait_type":"Determinism Hash","value":"0x', hashHex, '"}',
                ']}'
            );
        }
        return string.concat(
            'data:application/json;utf8,{"name":"', name, ' #', _toString(tokenId), '"',
            ',"description":"', collectionDescription, '"',
            ',"external_url":"', externalUrl, '"',
            ',"attributes":[',
                '{"trait_type":"Locked NORML (pixels)","value":', _toString(amt / 1e18), '},',
                '{"trait_type":"Determinism Hash","value":"0x', hashHex, '"}',
            ']}'
        );
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ERC-2981 ROYALTY                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.•°.•°:°.´+˚.*°.˚:*.´+°.•°:´*.´•*.•°.•*/

    /// @notice ERC-2981 — collection-wide royalty on every secondary sale.
    function royaltyInfo(uint256 /*tokenId*/, uint256 salePrice)
        external
        view
        returns (address receiver, uint256 royaltyAmount)
    {
        receiver = royaltyReceiver;
        royaltyAmount = (salePrice * royaltyBps) / 10_000;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                            VIEWS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.•°.•°:°.´+˚.*°.˚:*.´+°.•°:´*.´•*.•°.•*/

    /// @notice Enumerate token ids currently held by `holder` by scanning
    ///         minted ids. O(totalMinted) — fine for the 24-hour open edition.
    function tokensOfOwner(address holder)
        external
        view
        returns (uint256[] memory ids, uint256[] memory amounts, bytes32[] memory hashes)
    {
        uint256 bal = _balanceOf[holder];
        ids     = new uint256[](bal);
        amounts = new uint256[](bal);
        hashes  = new bytes32[](bal);
        if (bal == 0) return (ids, amounts, hashes);

        uint256 j;
        uint256 n = totalMinted;
        for (uint256 i = 0; i < n; i++) {
            if (_ownerOf[i] == holder) {
                ids[j] = i;
                amounts[j] = lockedAmount[i];
                hashes[j] = determinismHash[i];
                unchecked { j++; }
                if (j == bal) break;
            }
        }
    }

    /// @notice ERC-165 — advertise ERC-165, ERC-721, ERC-721Metadata,
    ///         ERC-4906, ERC-2981.
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return
            interfaceId == 0x01ffc9a7 || // ERC-165
            interfaceId == 0x80ac58cd || // ERC-721
            interfaceId == 0x5b5e139f || // ERC-721Metadata
            interfaceId == 0x49064906 || // ERC-4906
            interfaceId == 0x2a55205a;   // ERC-2981
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  ON-CHAIN MARKETPLACE IMAGE                */
    /*.•°:°.´+˚.*°.˚:*.´•*.•°.•°:°.´+˚.*°.˚:*.´+°.•°:´*.´•*.•°.•*/

    /// @dev Visual constants matching `scripts/gen-sample-svgs.js`. Output is a fixed
    ///      600-unit square so the N4M.### + pixel-count overlays render the same on-
    ///      screen size regardless of the underlying stake-window resolution.
    uint256 internal constant _SVG_SIZE      = 600;
    uint256 internal constant _SVG_PAD       = 28;
    uint256 internal constant _SVG_FONT_LBL  = 40;
    uint256 internal constant _SVG_FONT_PX   = 22;
    /// @dev `--accent` from web/app/norml.css.
    bytes   internal constant _ACCENT        = "#30d7e4";
    /// @dev `keccak256(seed, "pos")` mirror constant for shared randomness with NormlAssets.
    uint16  internal constant _VIEW_MARGIN_BPS = 500;

    /// @notice Build a complete `data:image/svg+xml;base64,...` URI for the marketplace
    ///         thumbnail of `tokenId`. Reads the source webp from `NormlAssets._assetChunks`
    ///         (single source of truth — same bundle used by the live shader), extracts the
    ///         `"main"` data URI, computes the crop window from the same `(artworkId, xBps,
    ///         yBps, pixels)` derivation as `animationURIForMe`, and emits the SVG.
    function _imageURIForMe(address assets, uint256 tokenId, uint256 amt, bytes32 h)
        internal
        view
        returns (string memory)
    {
        uint256 artworkId = uint256(h) % 9;
        uint256 pixels    = amt / 1e18;
        uint16 W = INormlAssets(assets).CANVAS_W(artworkId);
        uint16 H = INormlAssets(assets).CANVAS_H(artworkId);
        (uint16 xBps, uint16 yBps) = _randomPosition(h, W, H, pixels);

        string memory webp = _extractMainWebp(assets, artworkId);
        bytes memory svg = _buildSvg(webp, W, H, xBps, yBps, pixels, tokenId);
        return string.concat("data:image/svg+xml;base64,", Base64.encode(svg));
    }

    /// @dev Read concatenated SSTORE2 chunks of `_assetChunks[artworkId]` (already base64-
    ///      encoded ASCII), base64-decode to the JS asset bundle, and extract the value
    ///      of the embedded `{"main":"data:image/webp;base64,..."}` field.
    ///      We exploit the FIXED prefix `window.ARTWORK_ASSETS={"main":"` (31 bytes, hard-
    ///      coded by the upload script) — `data:image/webp;base64,` therefore starts at
    ///      decoded offset 31, the webp body starts at offset 54, and the value terminates
    ///      at the next `"`.
    function _extractMainWebp(address assets, uint256 artworkId) internal view returns (string memory) {
        address[] memory chunks = INormlAssets(assets).getTokenChunks(artworkId);
        bytes memory encoded = _readChunks(chunks);
        bytes memory decoded = Base64.decode(string(encoded));

        uint256 dLen = decoded.length;
        uint256 end = 54;
        while (end < dLen && decoded[end] != 0x22) {
            unchecked { end++; }
        }
        // Slice decoded[31..end] = `data:image/webp;base64,<webp-b64>`
        uint256 outLen = end - 31;
        bytes memory out = new bytes(outLen);
        for (uint256 i = 0; i < outLen; i++) {
            out[i] = decoded[31 + i];
        }
        return string(out);
    }

    /// @dev Two-pass extcodecopy concat. Each SSTORE2 chunk's first byte is a STOP opcode
    ///      that we skip. Matches the layout `NormlAssets._readChunkedData` uses internally.
    function _readChunks(address[] memory chunks) internal view returns (bytes memory result) {
        uint256 n = chunks.length;
        if (n == 0) return result;
        uint256 total;
        for (uint256 i = 0; i < n; i++) {
            address c = chunks[i];
            uint256 sz;
            assembly { sz := extcodesize(c) }
            unchecked { total += sz - 1; }
        }
        result = new bytes(total);
        uint256 off;
        for (uint256 i = 0; i < n; i++) {
            address c = chunks[i];
            uint256 sz;
            assembly {
                sz := sub(extcodesize(c), 1)
                extcodecopy(c, add(add(result, 0x20), off), 1, sz)
            }
            unchecked { off += sz; }
        }
    }

    /// @dev Build the SVG body. Layout mirrors `scripts/gen-sample-svgs.js` exactly:
    ///      black background, transform-scaled cropped webp, centered white `N4M.###`,
    ///      bottom-right accent-color `{n} $NORML`. All overlays at fixed 600-unit coords
    ///      so type size is identical at every stake-window resolution.
    function _buildSvg(
        string memory webpDataUri,
        uint16 W,
        uint16 H,
        uint16 xBps,
        uint16 yBps,
        uint256 pixels,
        uint256 tokenId
    ) internal pure returns (bytes memory) {
        uint256 side = _ceilSqrt(pixels == 0 ? 1 : pixels);
        // Center coords in canvas space, edge-clamped so the window stays inside (0..W, 0..H).
        uint256 cx = (uint256(xBps) * W) / 10000;
        uint256 cy = (uint256(yBps) * H) / 10000;
        uint256 half = side / 2;
        if (cx < half) cx = half; if (cx + half > W) cx = W - half;
        if (cy < half) cy = half; if (cy + half > H) cy = H - half;

        // SVG transform: scale s = SIZE/side so the side-sized window fills 600, then
        // translate so (cx,cy) lands at the SVG center (300,300).
        // To avoid floating point: render as `scale(SIZE) translate(...)` and divide
        // coords by `side` in the translate string — both forms produce identical
        // pixels since we feed integer image dims to the inner <image>.
        // Implementation: emit `scale(SIZE / side)` as a decimal with up to 6 fraction digits.
        (string memory s,  ) = _div(_SVG_SIZE * 1_000_000, side); // s = scale * 1e6 in string form ".XXXXXX"
        // Translate components: tx = SIZE/2 - cx*scale, ty = SIZE/2 - cy*scale.
        // Compute in 1e6 fixed point and emit as signed decimal.
        int256 txN = int256(_SVG_SIZE * 500_000) - int256(cx * (_SVG_SIZE * 1_000_000) / side) / 1;
        int256 tyN = int256(_SVG_SIZE * 500_000) - int256(cy * (_SVG_SIZE * 1_000_000) / side) / 1;

        bytes memory head = abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 600 600" width="600" height="600">',
            '<rect width="600" height="600" fill="#0a0a0a"/>',
            '<g clip-path="inset(0)" image-rendering="pixelated" shape-rendering="crispEdges" style="image-rendering:pixelated;image-rendering:-moz-crisp-edges;image-rendering:crisp-edges">',
            '<g transform="translate(', _fmtFixed6(txN), ' ', _fmtFixed6(tyN), ') scale(', s, ')">',
            '<image href="', webpDataUri, '" x="0" y="0" width="', _toString(W), '" height="', _toString(H),
            '" preserveAspectRatio="none" image-rendering="pixelated" style="image-rendering:pixelated;image-rendering:-moz-crisp-edges;image-rendering:crisp-edges"/>',
            '</g></g>'
        );
        bytes memory tail = abi.encodePacked(
            '<g font-family="ui-monospace, SFMono-Regular, Menlo, monospace" font-weight="500">',
            '<text x="300" y="300" text-anchor="middle" dominant-baseline="middle" font-size="40" fill="#ffffff" letter-spacing="2">N4M.',
            _pad3(tokenId),
            '</text>',
            '<text x="572" y="572" text-anchor="end" font-size="22" fill="', _ACCENT, '">',
            _toString(pixels), ' $NORML',
            '</text></g></svg>'
        );
        return bytes.concat(head, tail);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  POSITION ALGORITHM (mirror)               */
    /*.•°:°.´+˚.*°.˚:*.´•*.•°.•°:°.´+˚.*°.˚:*.´+°.•°:´*.´•*.•°.•*/

    /// @dev Pinwheel-side position picker. MUST stay byte-for-byte identical to
    ///      `NormlAssets._randomPosition` so the image window matches the live shader.
    function _randomPosition(bytes32 seed, uint16 W, uint16 H, uint256 pixels)
        internal pure returns (uint16 xBps, uint16 yBps)
    {
        uint256 stakeSide = _ceilSqrt(pixels);
        uint256 hx = W == 0 ? 0 : (stakeSide * 10000) / (2 * uint256(W));
        uint256 hy = H == 0 ? 0 : (stakeSide * 10000) / (2 * uint256(H));
        hx += _VIEW_MARGIN_BPS;
        hy += _VIEW_MARGIN_BPS;
        if (hx > 5000) hx = 5000;
        if (hy > 5000) hy = 5000;

        uint256 r = uint256(keccak256(abi.encode(seed, "pos")));
        uint256 side = r & 0x3;
        uint256 rx = (r >> 64) % 10001;
        uint256 ry = (r >> 128) % 10001;

        uint256 xLo; uint256 xHi; uint256 yLo; uint256 yHi;
        if (side == 0)       { xLo = 0;        xHi = 5000 + hx; yLo = 0;        yHi = 5000 - hy; }
        else if (side == 1)  { xLo = 5000 + hx;xHi = 10000;     yLo = 0;        yHi = 5000 + hy; }
        else if (side == 2)  { xLo = 5000 - hx;xHi = 10000;     yLo = 5000 + hy;yHi = 10000;     }
        else                 { xLo = 0;        xHi = 5000 - hx; yLo = 5000 - hy;yHi = 10000;     }
        uint256 spanX = xHi > xLo ? xHi - xLo : 0;
        uint256 spanY = yHi > yLo ? yHi - yLo : 0;
        uint256 x = spanX == 0 ? xLo : xLo + (rx % (spanX + 1));
        uint256 y = spanY == 0 ? yLo : yLo + (ry % (spanY + 1));
        return (uint16(x), uint16(y));
    }

    function _ceilSqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) { y = z; z = (x / z + z) / 2; }
        return y * y < x ? y + 1 : y;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        STRING HELPERS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.•°.•°:°.´+˚.*°.˚:*.´+°.•°:´*.´•*.•°.•*/

    /// @dev Format a base-1e6 fixed-point integer as a decimal string ("123.456789" with
    ///      trailing zeros stripped from the fraction). Used for SVG transform values.
    function _fmtFixed6(int256 v) internal pure returns (string memory) {
        bool neg = v < 0;
        uint256 a = neg ? uint256(-v) : uint256(v);
        uint256 whole = a / 1_000_000;
        uint256 frac  = a % 1_000_000;
        string memory wholeStr = _toString(whole);
        if (frac == 0) {
            return neg ? string.concat("-", wholeStr) : wholeStr;
        }
        // Pad fraction to 6 digits, strip trailing zeros.
        bytes memory fb = bytes(_toString(frac));
        bytes memory padded = new bytes(6);
        uint256 lead = 6 - fb.length;
        for (uint256 i = 0; i < lead; i++) padded[i] = "0";
        for (uint256 i = 0; i < fb.length; i++) padded[lead + i] = fb[i];
        uint256 last = 6;
        while (last > 0 && padded[last - 1] == "0") { last--; }
        bytes memory trimmed = new bytes(last);
        for (uint256 i = 0; i < last; i++) trimmed[i] = padded[i];
        string memory body = string.concat(wholeStr, ".", string(trimmed));
        return neg ? string.concat("-", body) : body;
    }

    /// @dev Return `n * 1e6 / d` as a fixed-point decimal string (e.g. 18.750000 → "18.75").
    ///      Second return is unused; signature kept to avoid an extra named return.
    function _div(uint256 n, uint256 d) internal pure returns (string memory, uint256) {
        if (d == 0) return ("0", 0);
        return (_fmtFixed6(int256(n / d)), 0);
    }

    /// @dev Format `n` with comma thousands separators ("10000" → "10,000").
    function _fmtCommas(uint256 n) internal pure returns (string memory) {
        bytes memory s = bytes(_toString(n));
        uint256 len = s.length;
        if (len <= 3) return string(s);
        uint256 commas = (len - 1) / 3;
        bytes memory out = new bytes(len + commas);
        uint256 oi = out.length;
        uint256 cnt = 0;
        for (uint256 i = len; i > 0; i--) {
            oi--;
            out[oi] = s[i - 1];
            cnt++;
            if (cnt == 3 && i > 1) {
                oi--;
                out[oi] = ",";
                cnt = 0;
            }
        }
        return string(out);
    }

    function _pad3(uint256 n) internal pure returns (string memory) {
        if (n >= 100) return _toString(n);
        bytes memory out = new bytes(3);
        out[0] = "0";
        out[1] = n >= 10 ? bytes1(uint8(48 + (n / 10))) : bytes1("0");
        out[2] = bytes1(uint8(48 + (n % 10)));
        return string(out);
    }

    function _toString(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        uint256 tmp = v;
        uint256 digits;
        while (tmp != 0) { digits++; tmp /= 10; }
        bytes memory buf = new bytes(digits);
        while (v != 0) {
            digits--;
            buf[digits] = bytes1(uint8(48 + v % 10));
            v /= 10;
        }
        return string(buf);
    }

    function _bytes32ToHex(bytes32 v) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory out = new bytes(64);
        for (uint256 i = 0; i < 32; i++) {
            uint8 b = uint8(v[i]);
            out[2 * i]     = alphabet[b >> 4];
            out[2 * i + 1] = alphabet[b & 0x0f];
        }
        return string(out);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           RECEIVE                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.•°.•°:°.´+˚.*°.˚:*.´+°.•°:´*.´•*.•°.•*/

    /// @dev Accept stray ETH (e.g. royalty drips). Owner can withdraw.
    receive() external payable {}
}
