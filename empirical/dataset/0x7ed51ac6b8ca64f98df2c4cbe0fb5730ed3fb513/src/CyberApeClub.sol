// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC721A} from "erc721a/contracts/ERC721A.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {TraitStorage} from "./TraitStorage.sol";
import {CyberApeRenderer} from "./CyberApeRenderer.sol";

/// @title Cyber Ape Club — fully on-chain generative NFT (ERC721A)
/// @notice Image (SVG) and metadata are rendered on-chain by reading trait
///         fragments stored via SSTORE2 in a separate TraitStorage. Uses
///         ERC721A for cheap batch minting.
/// @dev Mint economics:
///         - Per wallet lifetime cap: MAX_PER_WALLET (20)
///         - First 1 mint per wallet is free
///         - Remaining mints cost MINT_PRICE (0.00033 ether) each
contract CyberApeClub is ERC721A, Ownable {
    uint256 public constant MAX_SUPPLY = 10_000;
    uint256 public constant MAX_PER_WALLET = 20;
    uint256 public constant FREE_PER_WALLET = 1;
    uint256 public constant MINT_PRICE = 0.00033 ether;

    /// @dev Hard cap on the duplicate-DNA retry loop. Keeps mint() gas bounded
    ///      if the trait storage is ever misconfigured.
    uint256 private constant MAX_DNA_TRIES = 16;

    TraitStorage public immutable traits;

    bool public mintOpen;

    /// @dev tokenId => seed used to render that ape. Stored per token because
    ///      ERC721A batches ownership but each ape needs its own DNA.
    mapping(uint256 => uint256) public seeds;

    /// @dev Guards against duplicate trait combinations.
    mapping(bytes32 => bool) public dnaUsed;

    error MintClosed();
    error SoldOut();
    error ZeroQuantity();
    error ExceedsWalletCap();
    error WrongValue();
    error NotMinted();
    error CouldNotFindUniqueDNA();

    constructor(TraitStorage traits_) ERC721A("Cyber Apes Club", "CAC") Ownable(msg.sender) {
        traits = traits_;
    }

    // ---------- Admin ----------

    function setMintOpen(bool open) external onlyOwner {
        mintOpen = open;
    }

    function withdraw(address payable to) external onlyOwner {
        uint256 amount = address(this).balance;
        require(amount > 0, "nothing to withdraw");
        (bool ok,) = to.call{value: amount}("");
        require(ok, "transfer failed");
    }

    // ---------- Mint ----------

    /// @notice Mint `quantity` apes. The caller's first mint is free; the
    ///         remaining mints cost MINT_PRICE each. Reverts if the wallet
    ///         would exceed MAX_PER_WALLET or the contract is sold out.
    function mint(uint256 quantity) external payable {
        if (!mintOpen) revert MintClosed();
        if (quantity == 0) revert ZeroQuantity();
        if (_totalMinted() + quantity > MAX_SUPPLY) revert SoldOut();

        uint256 alreadyMinted = _numberMinted(msg.sender);
        if (alreadyMinted + quantity > MAX_PER_WALLET) revert ExceedsWalletCap();

        uint256 freeRemaining = alreadyMinted >= FREE_PER_WALLET ? 0 : FREE_PER_WALLET - alreadyMinted;
        uint256 freeNow = quantity < freeRemaining ? quantity : freeRemaining;
        uint256 paid = quantity - freeNow;
        if (msg.value != paid * MINT_PRICE) revert WrongValue();

        uint256 startId = _nextTokenId();
        for (uint256 i; i < quantity; ++i) {
            seeds[startId + i] = _findUniqueSeed(startId + i);
        }
        _mint(msg.sender, quantity);
    }

    function _findUniqueSeed(uint256 tokenId) internal returns (uint256) {
        for (uint256 nonce; nonce < MAX_DNA_TRIES; ++nonce) {
            uint256 seed = uint256(
                keccak256(abi.encodePacked(block.prevrandao, block.timestamp, msg.sender, tokenId, nonce))
            );
            bytes32 dna = CyberApeRenderer.dnaOf(traits, seed);
            if (!dnaUsed[dna]) {
                dnaUsed[dna] = true;
                return seed;
            }
        }
        revert CouldNotFindUniqueDNA();
    }

    // ---------- Views ----------

    function totalMinted() external view returns (uint256) {
        return _totalMinted();
    }

    function numberMinted(address owner) external view returns (uint256) {
        return _numberMinted(owner);
    }

    /// @notice Price in wei to mint `quantity` apes for `wallet`. Accounts for
    ///         the wallet's remaining free allocation.
    function priceFor(address wallet, uint256 quantity) external view returns (uint256) {
        uint256 alreadyMinted = _numberMinted(wallet);
        if (alreadyMinted >= FREE_PER_WALLET) return quantity * MINT_PRICE;
        uint256 freeRemaining = FREE_PER_WALLET - alreadyMinted;
        uint256 freeNow = quantity < freeRemaining ? quantity : freeRemaining;
        return (quantity - freeNow) * MINT_PRICE;
    }

    // ---------- Metadata ----------

    /// @dev ERC721A starts token ids at 0 by default; we want #1 to be the
    ///      first one minted so users see human-friendly ids.
    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (!_exists(tokenId)) revert NotMinted();
        return CyberApeRenderer.tokenURI(traits, tokenId, seeds[tokenId]);
    }
}
