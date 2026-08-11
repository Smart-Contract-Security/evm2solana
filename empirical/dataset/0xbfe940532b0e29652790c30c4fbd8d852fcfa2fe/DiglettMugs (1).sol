// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;                    // locked — no range check overhead

// ─────────────────────────────────────────────────────────────────────────────
//  Diglett Mugs — ERC-721
//  Symbol   : DM        Supply  : 5,000
//  Price    : 0.0003 ETH (owner-adjustable)
//  Max/Tx   : 10 (public) — unlimited (owner)
//  Royalty  : 5% EIP-2981
//  Compiler : 0.8.35+commit.47b9dedd
//  Optimizer: 200 runs recommended
//
//  ── Storage layout ───────────────────────────────────────────────────────────
//  Slot 0  │ _royaltyReceiver (address, 20 B) — only touched on royalty ops
//  Slot 1  │ mintPrice (uint96, 12 B) · _nextId (uint16, 2 B) · mintOpen (bool, 1 B)
//          │ All three are read in a single SLOAD on every mint call.
// ─────────────────────────────────────────────────────────────────────────────

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract DiglettMugs is ERC721, Ownable, IERC2981 {
    using Strings for uint256;

    // ── Custom errors ─────────────────────────────────────────────────────────
    error MintClosed();
    error InvalidQuantity();
    error ExceedsSupply();
    error InsufficientEth();
    error WithdrawFailed();
    error NothingToWithdraw();
    error ZeroAddress();

    // ── Constants (inlined by compiler — zero storage cost) ──────────────────
    uint256 public constant MAX_SUPPLY = 5_000;
    uint256 public constant MAX_PER_TX = 10;
    uint96  private constant ROYALTY_BPS = 500;      // 500/10000 = 5%

    // ── Slot 0: royalty receiver only (20 / 32 bytes) ────────────────────────
    address private _royaltyReceiver;

    // ── Slot 1: mint hot-path (15 / 32 bytes) ────────────────────────────────
    //  All three fields are packed into one slot and fetched in a single SLOAD
    //  inside mint(), saving one cold SLOAD (~2100 gas) per mint transaction
    //  compared to spreading them across two slots.
    uint96  public mintPrice = 0.0003 ether;         // 12 bytes ─┐
    uint16  private _nextId  = 1;                    //  2 bytes  │ slot 1
    bool    public  mintOpen = true;                 //  1 byte  ─┘

    // ── Metadata ──────────────────────────────────────────────────────────────
    string private _base =
        "ipfs://bafybeifbt4rd4shoen67n6d7acjboqn4erlo5oc27rbt3mjf53ibzrlos4/";

    // ── Events ────────────────────────────────────────────────────────────────
    event Minted(address indexed to, uint256 quantity);
    event MintPriceUpdated(uint96 newPrice);
    event MintToggled(bool open);
    event Withdrawn(uint256 amount);

    // ── Constructor ───────────────────────────────────────────────────────────
    constructor() ERC721("Diglett Mugs", "DM") Ownable(msg.sender) {
        _royaltyReceiver = msg.sender;
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  PUBLIC MINT
    //
    //  Gas notes:
    //  · mintOpen, mintPrice, _nextId all live in slot 1 — one cold SLOAD
    //    fetches all three simultaneously.
    //  · _nextId is read into `start` once and written back once (one SSTORE)
    //    rather than incrementing inside the loop.
    //  · _mint is used instead of _safeMint — skips the ERC721Receiver callback,
    //    saving ~2 000 gas per token for EOA minters.
    //  · No overpay refund — caller must send exact or excess ETH is kept.
    //    Reverts only if msg.value < required.
    // ─────────────────────────────────────────────────────────────────────────
    function mint(uint256 quantity) external payable {
        // Single SLOAD fetches mintOpen + mintPrice + _nextId (all in slot 1)
        bool   _open  = mintOpen;
        uint96 _price = mintPrice;
        uint256 start = _nextId;             // uint16 → uint256, no overflow

        if (!_open)                                       revert MintClosed();
        if (quantity == 0 || quantity > MAX_PER_TX)       revert InvalidQuantity();
        if (msg.value < uint256(_price) * quantity)       revert InsufficientEth();

        unchecked {
            // start >= 1 and quantity >= 1, so start + quantity >= 2
            // MAX_SUPPLY + 1 = 5001 is a compile-time constant
            if (start + quantity > MAX_SUPPLY + 1)        revert ExceedsSupply();

            // Write counter once (one SSTORE) — never inside the loop
            _nextId = uint16(start + quantity);           // max 5001, safe in uint16

            for (uint256 i; i < quantity; ++i) {
                _mint(msg.sender, start + i);
            }
        }

        emit Minted(msg.sender, quantity);
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  OWNER MINT
    //  · No price check, no per-tx cap, no mintOpen check.
    //  · MAX_SUPPLY is still enforced — hard cap is unconditional.
    //  · Accepts any quantity > 0.
    // ─────────────────────────────────────────────────────────────────────────
    function ownerMint(address to, uint256 quantity) external onlyOwner {
        if (to == address(0))    revert ZeroAddress();
        if (quantity == 0)       revert InvalidQuantity();

        uint256 start = _nextId;

        unchecked {
            if (start + quantity > MAX_SUPPLY + 1) revert ExceedsSupply();
            _nextId = uint16(start + quantity);

            for (uint256 i; i < quantity; ++i) {
                _mint(to, start + i);
            }
        }

        emit Minted(to, quantity);
    }

    // ── Token URI ─────────────────────────────────────────────────────────────
    function tokenURI(uint256 tokenId)
        public view override
        returns (string memory)
    {
        _requireOwned(tokenId);
        return string(abi.encodePacked(_base, tokenId.toString(), ".json"));
    }

    // ── EIP-2981 Royalty ──────────────────────────────────────────────────────
    // ROYALTY_BPS = 500, so royalty = salePrice * 500 / 10000 = salePrice / 20.
    // Written as division to avoid the multiplication (compiler inlines constants
    // but explicit division is cleaner and equally correct here).
    function royaltyInfo(uint256 /*tokenId*/, uint256 salePrice)
        external view override
        returns (address receiver, uint256 royaltyAmount)
    {
        unchecked {
            return (_royaltyReceiver, salePrice / 20);
        }
    }

    // ── Interface support ─────────────────────────────────────────────────────
    function supportsInterface(bytes4 interfaceId)
        public view override(ERC721, IERC165)
        returns (bool)
    {
        return
            interfaceId == type(IERC2981).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    // ── Owner-only controls ───────────────────────────────────────────────────

    /// @notice Set mint price per token (in wei).
    function setMintPrice(uint96 newPrice) external onlyOwner {
        mintPrice = newPrice;
        emit MintPriceUpdated(newPrice);
    }

    /// @notice Open or close public minting.
    function setMintOpen(bool open) external onlyOwner {
        mintOpen = open;
        emit MintToggled(open);
    }

    /// @notice Update base metadata URI (emergency migration).
    function setBaseURI(string calldata newURI) external onlyOwner {
        _base = newURI;
    }

    /// @notice Update EIP-2981 royalty receiver address.
    function setRoyaltyReceiver(address receiver) external onlyOwner {
        if (receiver == address(0)) revert ZeroAddress();
        _royaltyReceiver = receiver;
    }

    /// @notice Withdraw full ETH balance to owner wallet.
    function withdraw() external onlyOwner {
        uint256 bal = address(this).balance;
        if (bal == 0) revert NothingToWithdraw();
        // Cache owner() — avoids a second SLOAD into Ownable's storage slot.
        address payable to = payable(owner());
        (bool ok, ) = to.call{value: bal}("");
        if (!ok) revert WithdrawFailed();
        emit Withdrawn(bal);
    }

    // ── Read helpers ──────────────────────────────────────────────────────────

    /// @notice Total tokens minted so far.
    function totalMinted() external view returns (uint256) {
        unchecked { return _nextId - 1; }
    }

    /// @notice Tokens still available to mint.
    function remaining() external view returns (uint256) {
        unchecked { return MAX_SUPPLY - (_nextId - 1); }
    }
}
