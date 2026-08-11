// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @title MintCollection
/// @notice ERC-721 collection gated behind EIP-7702 burner-delegate delegation.
///         Only EOAs that have delegated to the canonical BurnerDelegate implementation
///         may call `mint`. Royalties follow EIP-2981.
contract MintCollection is ERC721, ERC2981, Ownable, ReentrancyGuardTransient {
    using Strings for uint256;

    // -------------------------------------------------------------------------
    // Immutables
    // -------------------------------------------------------------------------

    /// @notice The canonical BurnerDelegate implementation address used for EIP-7702 check.
    address public immutable BURNER_DELEGATE_IMPLEMENTATION;

    /// @notice Recipient of all mint proceeds and royalties.
    address public immutable TREASURY;

    /// @notice Maximum number of tokens that can ever be minted.
    uint256 public immutable MAX_SUPPLY;

    /// @notice Royalty expressed in basis points (50 = 0.5%).
    uint16 public constant ROYALTY_BPS = 50;

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    /// @notice Current sequential token ID counter. First minted token is ID 1.
    uint256 private _tokenIdCounter;

    /// @notice Whether minting is currently enabled.
    bool public mintActive;

    /// @notice Base URI prepended to all token URIs (e.g. "ipfs://Qm.../").
    string private _baseTokenURI;

    /// @notice Required ETH payment per mint. Owner may change it between phases
    ///         (e.g. WL discount → public price), then optionally call lockPrice()
    ///         to permanently freeze it. After lock, setMintPrice reverts.
    uint256 public mintPrice;

    /// @notice Once true, mintPrice is frozen forever. One-way switch.
    bool public mintPriceLocked;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event MintActiveChanged(bool active);
    event BaseURIUpdated(string newBaseURI);
    event ProceedsWithdrawn(address indexed to, uint256 amount);
    event MintPriceUpdated(uint256 oldPrice, uint256 newPrice);
    event MintPriceLocked(uint256 finalPrice);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /// @param burnerDelegateImpl  Canonical BurnerDelegate implementation address.
    /// @param treasury            Address to receive proceeds and royalties.
    /// @param initialOwner        Address granted ownership.
    /// @param initialBaseURI      Initial base URI (e.g. "https://blobsters.xyz/api/metadata/").
    /// @param maxSupply           Hard cap on token supply.
    /// @param initialMintPrice    Starting mint price in wei. Mutable until lockPrice().
    constructor(
        address burnerDelegateImpl,
        address treasury,
        address initialOwner,
        string memory initialBaseURI,
        uint256 maxSupply,
        uint256 initialMintPrice
    ) ERC721("Blobsters", "BLOB") Ownable(initialOwner) {
        require(burnerDelegateImpl != address(0), "zero impl");
        require(treasury != address(0), "zero treasury");
        require(maxSupply > 0, "zero supply");

        BURNER_DELEGATE_IMPLEMENTATION = burnerDelegateImpl;
        TREASURY = treasury;
        MAX_SUPPLY = maxSupply;
        mintPrice = initialMintPrice;
        mintActive = true;
        _baseTokenURI = initialBaseURI;

        // Set default royalty: TREASURY receives ROYALTY_BPS basis points.
        _setDefaultRoyalty(treasury, ROYALTY_BPS);
    }

    // -------------------------------------------------------------------------
    // Mint
    // -------------------------------------------------------------------------

    /// @notice Mint a single token to `to`.
    /// @dev Caller MUST be the canonical BurnerDelegate contract. The delegate, in turn,
    ///      requires a backend-signed intent — so direct mints bypassing the Twitter flow
    ///      are impossible. Exactly `mintPrice` ETH must be sent.
    function mint(address to) external payable nonReentrant {
        require(mintActive, "mint not active");
        require(msg.sender == BURNER_DELEGATE_IMPLEMENTATION, "only delegate");
        require(msg.value == mintPrice, "wrong value");
        require(to != address(0), "zero to");
        require(_tokenIdCounter < MAX_SUPPLY, "sold out");

        // Checks-Effects: increment counter before external _safeMint call.
        _tokenIdCounter += 1;
        uint256 tokenId = _tokenIdCounter;

        _safeMint(to, tokenId);
    }

    // -------------------------------------------------------------------------
    // Token URI
    // -------------------------------------------------------------------------

    /// @notice Returns URI for `tokenId` in the form `baseURI + tokenId + ".json"`.
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        return string(abi.encodePacked(_baseTokenURI, tokenId.toString(), ".json"));
    }

    // -------------------------------------------------------------------------
    // Owner functions
    // -------------------------------------------------------------------------

    /// @notice Update the base URI. Call after IPFS upload to reveal metadata.
    function setBaseURI(string calldata newBaseURI) external onlyOwner {
        _baseTokenURI = newBaseURI;
        emit BaseURIUpdated(newBaseURI);
    }

    /// @notice Enable or disable minting.
    function setMintActive(bool active) external onlyOwner {
        mintActive = active;
        emit MintActiveChanged(active);
    }

    /// @notice Update mintPrice. Reverts after lockPrice() has been called.
    ///         Intended for WL→public phase transitions.
    function setMintPrice(uint256 newPrice) external onlyOwner {
        require(!mintPriceLocked, "price locked");
        emit MintPriceUpdated(mintPrice, newPrice);
        mintPrice = newPrice;
    }

    /// @notice Permanently lock mintPrice. One-way operation — irreversible.
    ///         Use after public phase price is set to signal community
    ///         that price cannot be changed again.
    function lockPrice() external onlyOwner {
        require(!mintPriceLocked, "already locked");
        mintPriceLocked = true;
        emit MintPriceLocked(mintPrice);
    }

    // -------------------------------------------------------------------------
    // Proceeds
    // -------------------------------------------------------------------------

    /// @notice Send the full ETH balance of this contract to TREASURY.
    ///         Anyone may call this — there is no privileged recipient.
    function withdrawProceeds() external {
        uint256 amount = address(this).balance;
        require(amount > 0, "nothing to withdraw");
        emit ProceedsWithdrawn(TREASURY, amount);
        (bool ok,) = TREASURY.call{value: amount}("");
        require(ok, "transfer failed");
    }

    // -------------------------------------------------------------------------
    // Royalties (EIP-2981)
    // -------------------------------------------------------------------------

    /// @notice Returns royalty info: (TREASURY, salePrice * ROYALTY_BPS / 10000).
    function royaltyInfo(uint256, uint256 salePrice)
        public
        view
        override
        returns (address receiver, uint256 royaltyAmount)
    {
        receiver = TREASURY;
        royaltyAmount = (salePrice * ROYALTY_BPS) / 10_000;
    }

    // -------------------------------------------------------------------------
    // Interface support
    // -------------------------------------------------------------------------

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC2981)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // -------------------------------------------------------------------------
    // View helpers
    // -------------------------------------------------------------------------

    /// @notice Returns the total number of tokens minted so far.
    function totalSupply() public view returns (uint256) {
        return _tokenIdCounter;
    }
}
