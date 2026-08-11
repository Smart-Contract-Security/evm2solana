// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "erc721a/contracts/ERC721A.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract TripperPunks is ERC721A, Ownable {
    using Strings for uint256;

    uint256 public constant MAX_SUPPLY = 10000;
    uint256 public PRICE = 0.0001 ether;

    string private baseTokenURI;

    mapping(address => bool) public blocked;
    mapping(address => uint256) public minted;

    constructor(string memory baseURI)
        ERC721A("TripperPunks", "TRIP")
        Ownable(msg.sender)
    {
        baseTokenURI = baseURI;
    }

    modifier notBlocked(address user) {
        require(!blocked[user], "Blocked");
        _;
    }

    function mint(uint256 amount) external payable notBlocked(msg.sender) {
        require(amount > 0, "Zero amount");
        require(totalSupply() + amount <= MAX_SUPPLY, "Sold out");

        uint256 cost;

        if (minted[msg.sender] == 0) {
            if (amount > 1) {
                cost = (amount - 1) * PRICE;
            }
        } else {
            cost = amount * PRICE;
        }

        require(msg.value >= cost, "Not enough ETH");

        minted[msg.sender] += amount;
        _safeMint(msg.sender, amount);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        require(_exists(tokenId), "Nonexistent");

        return string(
            abi.encodePacked(
                baseTokenURI,
                "/",
                tokenId.toString()
            )
        );
    }

    function blockWallet(address user) external onlyOwner {
        blocked[user] = true;
    }

    function unblockWallet(address user) external onlyOwner {
        blocked[user] = false;
    }

    function setBaseURI(string memory uri) external onlyOwner {
        baseTokenURI = uri;
    }

    function setPrice(uint256 newPrice) external onlyOwner {
        PRICE = newPrice;
    }

    function withdraw() external onlyOwner {
        (bool success, ) = payable(owner()).call{
            value: address(this).balance
        }("");

        require(success, "Withdraw failed");
    }

    function _baseURI()
        internal
        view
        override
        returns (string memory)
    {
        return baseTokenURI;
    }

    function _beforeTokenTransfers(
        address from,
        address to,
        uint256 startTokenId,
        uint256 quantity
    ) internal override {
        require(!blocked[from], "Sender blocked");
        require(!blocked[to], "Receiver blocked");

        super._beforeTokenTransfers(
            from,
            to,
            startTokenId,
            quantity
        );
    }
}