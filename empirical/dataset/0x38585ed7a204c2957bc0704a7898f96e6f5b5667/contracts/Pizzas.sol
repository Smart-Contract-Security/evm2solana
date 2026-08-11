// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "erc721a/contracts/ERC721A.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title Pizzas — pizza-themed NFT collection
/// @notice Free click-to-open box mechanic (1–3 NFTs, one claim per wallet)
///         + paid mint (up to 35 per tx, 0.00025 ETH each).
///         Batch minting via ERC721A: _safeMint(user, quantity) — never loops.
///         Rarity is defined entirely in IPFS metadata, not on-chain.
///
///         tokenURI format: baseURI + tokenId  (files have no .json extension)
///         Example: baseURI/1  →  metadata for token #1
contract Pizzas is ERC721A, Ownable {
    // ─── Constants ────────────────────────────────────────────────────────────

    uint256 public constant MAX_SUPPLY      = 10_000;
    uint256 public constant PAID_PRICE      = 0.00025 ether;
    uint256 public constant MAX_PER_TX      = 35;
    uint256 public constant MAX_FREE_AMOUNT = 3;

    // ─── State ────────────────────────────────────────────────────────────────

    bool public freeMintActive;
    bool public paidMintActive;

    string private _baseTokenURI;

    mapping(address => bool) public hasClaimed;

    // ─── Events ───────────────────────────────────────────────────────────────

    event FreeMint(address indexed minter, uint256 amount);
    event PaidMint(address indexed minter, uint256 quantity);
    event BaseURIUpdated(string newBaseURI);
    event Withdrawn(address indexed to, uint256 amount);

    // ─── Constructor ──────────────────────────────────────────────────────────

    constructor(string memory baseURI_, address initialOwner_)
        ERC721A("PIZZAS", "PIZZA")
        Ownable(initialOwner_)
    {
        _baseTokenURI = baseURI_;
    }

    // ─── Mint ─────────────────────────────────────────────────────────────────

    /// @notice Claim 1, 2, or 3 free NFTs. One claim per wallet.
    /// @dev Amount is chosen client-side by the box-opening mechanic
    ///      (Math.random, distribution 30/40/30). Contract only validates range.
    ///      ERC721A mints the entire batch in one _safeMint call — no loop.
    function freeMint(uint256 amount) external {
        require(freeMintActive,                           "Free mint not active");
        require(!hasClaimed[msg.sender],                  "Already claimed");
        require(amount >= 1 && amount <= MAX_FREE_AMOUNT, "Amount must be 1, 2, or 3");
        require(totalSupply() + amount <= MAX_SUPPLY,     "Exceeds max supply");

        hasClaimed[msg.sender] = true;
        _safeMint(msg.sender, amount);

        emit FreeMint(msg.sender, amount);
    }

    /// @notice Paid mint: 1–35 NFTs per transaction at PAID_PRICE each.
    /// @dev ERC721A mints the entire batch in one _safeMint call — no loop.
    function paidMint(uint256 quantity) external payable {
        require(paidMintActive,                           "Paid mint not active");
        require(quantity >= 1 && quantity <= MAX_PER_TX,  "Quantity must be 1-35");
        require(msg.value == PAID_PRICE * quantity,       "Wrong ETH amount");
        require(totalSupply() + quantity <= MAX_SUPPLY,   "Exceeds max supply");

        _safeMint(msg.sender, quantity);

        emit PaidMint(msg.sender, quantity);
    }

    // ─── Owner ────────────────────────────────────────────────────────────────

    function setBaseURI(string calldata baseURI_) external onlyOwner {
        _baseTokenURI = baseURI_;
        emit BaseURIUpdated(baseURI_);
    }

    function setFreeMintActive(bool active_) external onlyOwner {
        freeMintActive = active_;
    }

    function setPaidMintActive(bool active_) external onlyOwner {
        paidMintActive = active_;
    }

    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "Nothing to withdraw");
        (bool ok, ) = payable(owner()).call{ value: balance }("");
        require(ok, "Withdraw failed");
        emit Withdrawn(owner(), balance);
    }

    // ─── Internal ─────────────────────────────────────────────────────────────

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    /// @dev Token IDs start at 1, matching IPFS metadata files named 1, 2, 3…
    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }
}
