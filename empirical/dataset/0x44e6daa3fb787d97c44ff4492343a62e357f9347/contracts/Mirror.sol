// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "./src/tokens/ERC721.sol";
import {Ownable} from "./src/auth/Ownable.sol";
import {ReentrancyGuard} from "./src/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "./src/utils/SafeTransferLib.sol";

/// @notice Interface for the separately deployed MirrorRenderer.
interface IMirrorRenderer {
    function tokenURI(uint256 id, uint8 relation) external pure returns (string memory);
    function svgFor(uint256 id, uint8 relation) external pure returns (string memory);
}

/// @notice `mirror` — 10,000 split-face identities, fully on-chain.
/// @dev Mint pricing: first token per wallet is free; every subsequent token
///      costs PRICE each. Up to MAX_BATCH tokens per transaction.
///      Renderer is deployed separately to keep mint gas low.
contract Mirror is ERC721, Ownable, ReentrancyGuard {
    using SafeTransferLib for address;

    // -----------------------------------------------------------------------
    // Errors
    // -----------------------------------------------------------------------
    error MaxSupply();
    error WrongPrice();
    error MintClosed();
    error NonexistentToken();
    error WithdrawFailed();
    error ZeroQuantity();
    error ExceedsBatchLimit();

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------
    event Minted(address indexed to, uint256 startId, uint256 quantity, uint256 paid);

    // -----------------------------------------------------------------------
    // Constants
    // -----------------------------------------------------------------------
    uint256 public constant MAX_SUPPLY  = 10_000;
    uint256 public constant PRICE       = 0.0006 ether; // per token after the free one
    uint256 public constant MAX_BATCH   = 20;           // max tokens per mint call

    // -----------------------------------------------------------------------
    // State
    // -----------------------------------------------------------------------
    IMirrorRenderer public immutable renderer;

    uint256 public totalSupply;
    bool    public mintOpen;

    /// @notice True once a wallet has claimed its one free token.
    mapping(address => bool) public claimedFree;

    /// @notice hasHeld[id][addr] — true once addr has owned `id`.
    mapping(uint256 => mapping(address => bool)) public hasHeld;

    // -----------------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------------
    constructor(address renderer_) {
        renderer = IMirrorRenderer(renderer_);
        _initializeOwner(msg.sender);
    }

    function name()   public pure override returns (string memory) { return "mirror"; }
    function symbol() public pure override returns (string memory) { return "MIRROR"; }

    // -----------------------------------------------------------------------
    // Mint
    // -----------------------------------------------------------------------

    /// @notice Mint `quantity` tokens (1–20).
    /// @dev    First token is free for wallets that haven't claimed yet;
    ///         all others cost PRICE each.
    ///         Exact ETH required: msg.value == paidCount * PRICE
    function mint(uint256 quantity) external payable nonReentrant {
        if (!mintOpen)                  revert MintClosed();
        if (quantity == 0)              revert ZeroQuantity();
        if (quantity > MAX_BATCH)       revert ExceedsBatchLimit();
        if (totalSupply + quantity > MAX_SUPPLY) revert MaxSupply();

        // Determine how many paid tokens are in this batch.
        uint256 paidCount;
        if (claimedFree[msg.sender]) {
            // No free credit left — all tokens in this batch are paid.
            paidCount = quantity;
        } else {
            // First token in the VERY FIRST mint is free; rest are paid.
            claimedFree[msg.sender] = true;
            paidCount = quantity - 1; // 0 if quantity == 1
        }

        uint256 cost = paidCount * PRICE;
        if (msg.value != cost) revert WrongPrice();

        uint256 startId = totalSupply;
        unchecked { totalSupply += quantity; }

        for (uint256 i; i < quantity; ++i) {
            _mint(msg.sender, startId + i);
        }

        emit Minted(msg.sender, startId, quantity, cost);
    }

    // -----------------------------------------------------------------------
    // Owner controls
    // -----------------------------------------------------------------------
    function setMintOpen(bool open) external onlyOwner { mintOpen = open; }

    function withdraw(address to) external onlyOwner {
        (bool ok,) = to.call{value: address(this).balance}("");
        if (!ok) revert WithdrawFailed();
    }

    // -----------------------------------------------------------------------
    // Mirror mechanic — holder tracking
    // -----------------------------------------------------------------------
    function _afterTokenTransfer(address, address to, uint256 id) internal override {
        if (to != address(0)) hasHeld[id][to] = true;
    }

    /// @notice Viewer relation to token: 0=owner, 1=stranger, 2=former holder.
    function relationOf(uint256 id, address viewer) public view returns (uint8) {
        if (_ownerOf(id) == viewer)  return 0; // OWNER
        if (hasHeld[id][viewer])     return 2; // FORMER holder
        return 1;                              // STRANGER
    }

    // -----------------------------------------------------------------------
    // tokenURI — delegates to the separately deployed renderer
    // -----------------------------------------------------------------------

    /// @notice Marketplace-safe: always returns owner view.
    function tokenURI(uint256 id) public view override returns (string memory) {
        if (_ownerOf(id) == address(0)) revert NonexistentToken();
        return renderer.tokenURI(id, 0);
    }

    /// @notice Viewer-aware: the dapp passes the connected wallet.
    function tokenURIFor(uint256 id, address viewer) external view returns (string memory) {
        if (_ownerOf(id) == address(0)) revert NonexistentToken();
        return renderer.tokenURI(id, relationOf(id, viewer));
    }

    /// @notice Raw SVG for gallery/arena UI.
    function svgFor(uint256 id, address viewer) external view returns (string memory) {
        if (_ownerOf(id) == address(0)) revert NonexistentToken();
        return renderer.svgFor(id, relationOf(id, viewer));
    }

    // -----------------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------------

    /// @notice Returns the cost for `quantity` tokens for `wallet`.
    ///         Useful for the mint UI to pre-calculate msg.value.
    function mintCost(address wallet, uint256 quantity) external view returns (uint256) {
        if (quantity == 0 || quantity > MAX_BATCH) return type(uint256).max; // invalid
        uint256 paidCount = claimedFree[wallet] ? quantity : quantity - 1;
        return paidCount * PRICE;
    }
}
