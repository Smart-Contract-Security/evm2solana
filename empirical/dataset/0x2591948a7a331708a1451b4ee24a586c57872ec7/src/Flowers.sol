// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "erc721a/contracts/ERC721A.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";

/// @title  flowers
/// @notice 333 generative pixel flowers. Token #N renders seed N in the on-seed engine.
///         Fully creator-owned ERC721A drop with on-chain royalties.
contract Flowers is ERC721A, ERC2981, Ownable {
    uint256 public constant MAX_SUPPLY = 333;
    uint256 public price = 0.0033 ether;
    bool public saleActive;
    string private _baseTokenURI;

    constructor(string memory baseURI, address royaltyReceiver)
        ERC721A("flowers", "FLWR")
        Ownable(msg.sender)
    {
        _baseTokenURI = baseURI;
        _setDefaultRoyalty(royaltyReceiver, 500); // 5%
    }

    /// tokens are #1..#333 so token id == seed
    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }

    function mint(uint256 quantity) external payable {
        require(saleActive, "sale not active");
        require(quantity > 0, "qty 0");
        require(_totalMinted() + quantity <= MAX_SUPPLY, "sold out");
        require(msg.value >= price * quantity, "wrong value");
        _mint(msg.sender, quantity);
    }

    /// @notice Owner mint for reserves. Mints the next sequential ids, so calling
    ///         this before opening the sale lets you claim the iconic early tokens.
    function ownerMint(address to, uint256 quantity) external onlyOwner {
        require(_totalMinted() + quantity <= MAX_SUPPLY, "exceeds supply");
        _mint(to, quantity);
    }

    function setSaleActive(bool active) external onlyOwner { saleActive = active; }
    function setPrice(uint256 newPrice) external onlyOwner { price = newPrice; }
    function setBaseURI(string calldata uri) external onlyOwner { _baseTokenURI = uri; }
    function setRoyalty(address receiver, uint96 bps) external onlyOwner {
        _setDefaultRoyalty(receiver, bps);
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "nonexistent token");
        return string(abi.encodePacked(_baseTokenURI, _toString(tokenId), ".json"));
    }

    function totalMinted() external view returns (uint256) {
        return _totalMinted();
    }

    /// @notice Collection-level metadata for marketplaces (OpenSea reads this).
    function contractURI() external view returns (string memory) {
        return string(abi.encodePacked(_baseTokenURI, "collection.json"));
    }

    function withdraw() external onlyOwner {
        (bool ok, ) = payable(owner()).call{value: address(this).balance}("");
        require(ok, "withdraw failed");
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721A, ERC2981)
        returns (bool)
    {
        return ERC721A.supportsInterface(interfaceId) || ERC2981.supportsInterface(interfaceId);
    }
}
