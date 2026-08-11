// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract WCLPunkMint is ERC721, ERC721URIStorage, ERC721Enumerable, Ownable {
    uint256 private _nextTokenId;
    uint256 public mintPrice = 150000000000000; // 0.00015 SOL in lamports
    uint256 public maxSupply = 3200;
    mapping(address => uint256) public mintedPerWallet;
    uint256 public maxPerWallet = 3;

    constructor() ERC721("WCL Punk Mint", "PUNK") Ownable(msg.sender) {}

    function mint(string memory uri) external payable {
        require(msg.value >= mintPrice, "Insufficient SOL");
        require(_nextTokenId < maxSupply, "Sold out");
        require(mintedPerWallet[msg.sender] < maxPerWallet, "Max 3 per wallet");

        uint256 tokenId = _nextTokenId++;
        _safeMint(msg.sender, tokenId);
        _setTokenURI(tokenId, uri);
        mintedPerWallet[msg.sender]++;
    }

    function totalMinted() external view returns (uint256) {
        return _nextTokenId;
    }

    function withdraw() external onlyOwner {
        address payable recipient = payable(owner());
        recipient.transfer(address(this).balance);
    }

    function _update(address to, uint256 tokenId, address auth) internal override(ERC721, ERC721Enumerable) returns (address) {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value) internal override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, value);
    }

    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721URIStorage, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}