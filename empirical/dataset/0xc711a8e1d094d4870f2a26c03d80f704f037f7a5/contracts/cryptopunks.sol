// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract CryptoPepenks is ERC721Enumerable, Ownable {
    using Strings for uint256;

    uint256 public constant MAX_SUPPLY = 10000;
    uint256 public constant PRICE = 0.0001 ether;

    string public baseURI =
        "ipfs://bafybeihn7j3xmv2y6scpnyxqcz4uafwkr47w4r63rxt75gqlrpz4koyeue/";

    bool public mintOpen = true;

    mapping(address => uint256) public minted;
    mapping(address => bool) public blacklisted;

    constructor() ERC721("Crypto Pepenks", "PEPENKS") Ownable(msg.sender) {}

    function mint(uint256 amount) external payable {
        require(mintOpen, "Mint closed");
        require(!blacklisted[msg.sender], "Wallet blocked");
        require(amount > 0, "Zero amount");
        require(totalSupply() + amount <= MAX_SUPPLY, "Sold out");

        uint256 freeMint = minted[msg.sender] == 0 ? 1 : 0;
        uint256 paidAmount = amount > freeMint ? amount - freeMint : 0;

        require(msg.value >= PRICE * paidAmount, "Not enough ETH");

        minted[msg.sender] += amount;

        for (uint256 i = 0; i < amount; i++) {
            _safeMint(msg.sender, totalSupply() + 1);
        }
    }

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");

        return string(
            abi.encodePacked(
                baseURI,
                tokenId.toString(),
                ".json"
            )
        );
    }

    function setBlacklisted(address wallet, bool blocked) external onlyOwner {
        blacklisted[wallet] = blocked;
    }

    function setMintOpen(bool open) external onlyOwner {
        mintOpen = open;
    }

    function setBaseURI(string calldata newBaseURI) external onlyOwner {
        baseURI = newBaseURI;
    }

    function _update(
        address to,
        uint256 tokenId,
        address auth
    )
        internal
        override(ERC721Enumerable)
        returns (address)
    {
        address from = _ownerOf(tokenId);

        require(!blacklisted[from], "Sender blocked");
        require(!blacklisted[to], "Receiver blocked");

        return super._update(to, tokenId, auth);
    }

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        override(ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function withdraw() external onlyOwner {
        (bool success, ) = payable(owner()).call{
            value: address(this).balance
        }("");

        require(success, "Withdraw failed");
    }
}