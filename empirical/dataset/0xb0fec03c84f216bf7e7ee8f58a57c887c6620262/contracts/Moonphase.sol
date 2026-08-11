// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "erc721a/contracts/ERC721A.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title Moonphase
 * @dev ERC721A NFT contract for Moonphase collection
 * 999 unique moon phases with different colors and cosmic effects
 */
contract Moonphase is ERC721A, Ownable, ReentrancyGuard {
    using Strings for uint256;

    // Collection settings
    uint256 public constant MAX_SUPPLY = 999;
    uint256 public constant MINT_PRICE = 0.0001 ether;
    uint256 public constant MAX_PER_WALLET = 10;

    // Metadata
    string private baseTokenURI;
    bool public revealed = false;
    string public notRevealedURI;

    // Sale state
    bool public publicSaleActive = false;

    // Tracking
    mapping(address => uint256) public mintedPerWallet;

    // Events
    event PublicSaleToggled(bool active);
    event BaseURIUpdated(string baseURI);
    event Revealed(string baseURI);

    constructor(
        string memory _initBaseURI,
        string memory _initNotRevealedURI
    ) ERC721A("Moonphase", "MOON") Ownable(msg.sender) {
        baseTokenURI = _initBaseURI;
        notRevealedURI = _initNotRevealedURI;
    }

    // ============ MINTING ============

    /**
     * @dev Public mint function
     * @param quantity Number of NFTs to mint
     */
    function mint(uint256 quantity) external payable nonReentrant {
        require(publicSaleActive, "Public sale not active");
        require(quantity > 0, "Must mint at least 1");
        require(_totalMinted() + quantity <= MAX_SUPPLY, "Exceeds max supply");
        require(
            mintedPerWallet[msg.sender] + quantity <= MAX_PER_WALLET,
            "Exceeds max per wallet"
        );
        require(msg.value >= MINT_PRICE * quantity, "Insufficient payment");

        mintedPerWallet[msg.sender] += quantity;
        _mint(msg.sender, quantity);
    }

    /**
     * @dev Owner mint for team/giveaways
     * @param to Address to mint to
     * @param quantity Number of NFTs to mint
     */
    function ownerMint(address to, uint256 quantity) external onlyOwner {
        require(_totalMinted() + quantity <= MAX_SUPPLY, "Exceeds max supply");
        _mint(to, quantity);
    }

    // ============ ADMIN ============

    /**
     * @dev Toggle public sale state
     */
    function togglePublicSale() external onlyOwner {
        publicSaleActive = !publicSaleActive;
        emit PublicSaleToggled(publicSaleActive);
    }

    /**
     * @dev Set base URI for revealed metadata
     * @param _baseTokenURI IPFS base URI
     */
    function setBaseURI(string memory _baseTokenURI) external onlyOwner {
        baseTokenURI = _baseTokenURI;
        emit BaseURIUpdated(_baseTokenURI);
    }

    /**
     * @dev Set not revealed URI
     * @param _notRevealedURI URI for unrevealed metadata
     */
    function setNotRevealedURI(string memory _notRevealedURI) external onlyOwner {
        notRevealedURI = _notRevealedURI;
    }

    /**
     * @dev Reveal the collection
     */
    function reveal() external onlyOwner {
        revealed = true;
        emit Revealed(baseTokenURI);
    }

    /**
     * @dev Withdraw contract balance to owner
     */
    function withdraw() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance to withdraw");
        
        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "Withdrawal failed");
    }

    // ============ METADATA ============

    /**
     * @dev Returns the base URI
     */
    function _baseURI() internal view virtual override returns (string memory) {
        return baseTokenURI;
    }

    /**
     * @dev Returns the token URI for a given token ID
     * @param tokenId Token ID to get URI for
     */
    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(_exists(tokenId), "Token does not exist");

        if (!revealed) {
            return notRevealedURI;
        }

        string memory baseURI = _baseURI();
        return
            bytes(baseURI).length > 0
                ? string(abi.encodePacked(baseURI, tokenId.toString(), ".json"))
                : "";
    }

    // ============ VIEW ============

    /**
     * @dev Get total minted count
     */
    function totalMinted() external view returns (uint256) {
        return _totalMinted();
    }

    /**
     * @dev Get remaining supply
     */
    function remainingSupply() external view returns (uint256) {
        return MAX_SUPPLY - _totalMinted();
    }

    /**
     * @dev Get tokens owned by address
     * @param owner Address to query
     */
    function tokensOfOwner(address owner)
        external
        view
        returns (uint256[] memory)
    {
        uint256 tokenCount = balanceOf(owner);
        uint256[] memory tokenIds = new uint256[](tokenCount);
        uint256 index = 0;

        for (uint256 i = 1; i <= _totalMinted(); i++) {
            if (_exists(i) && ownerOf(i) == owner) {
                tokenIds[index] = i;
                index++;
            }
        }

        return tokenIds;
    }
}
