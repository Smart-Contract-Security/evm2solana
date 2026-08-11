// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "erc721a/contracts/ERC721A.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";

contract SolicAbstract is ERC721A, Ownable2Step, ReentrancyGuard, ERC2981 {
    uint256 public constant MAX_SUPPLY = 5151;
    uint256 public mintPrice = 0.0003 ether;
    uint256 public maxPerTx = 5;
    uint256 public maxPerWallet = 10;
    bool public mintOpen;

    string private baseTokenURI;
    string private collectionContractURI;
    mapping(address => uint256) public mintedByWallet;

    event MintOpened();
    event MintClosed();
    event BaseURISet(string uri);
    event ContractURISet(string uri);
    event Withdraw(address indexed to, uint256 amount);

    constructor(
        string memory name_,
        string memory symbol_,
        address royaltyReceiver,
        string memory initialBaseURI,
        string memory initialContractURI
    ) ERC721A(name_, symbol_) Ownable(msg.sender) {
        require(royaltyReceiver != address(0), "Royalty zero address");
        baseTokenURI = initialBaseURI;
        collectionContractURI = initialContractURI;
        _setDefaultRoyalty(royaltyReceiver, 500);
    }

    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }

    function mint(uint256 quantity) external payable nonReentrant {
        require(mintOpen, "Mint closed");
        require(quantity > 0, "Zero quantity");
        require(quantity <= maxPerTx, "Exceeds max per tx");
        require(totalSupply() + quantity <= MAX_SUPPLY, "Sold out");
        require(mintedByWallet[msg.sender] + quantity <= maxPerWallet, "Exceeds wallet limit");
        require(msg.value == mintPrice * quantity, "Wrong ETH amount");

        mintedByWallet[msg.sender] += quantity;
        _safeMint(msg.sender, quantity);
    }

    function ownerMint(address to, uint256 quantity) external onlyOwner {
        require(to != address(0), "Zero address");
        require(quantity > 0, "Zero quantity");
        require(totalSupply() + quantity <= MAX_SUPPLY, "Sold out");
        _safeMint(to, quantity);
    }

    function openMint() external onlyOwner {
        mintOpen = true;
        emit MintOpened();
    }

    function closeMint() external onlyOwner {
        mintOpen = false;
        emit MintClosed();
    }

    function setMintPrice(uint256 newPrice) external onlyOwner {
        mintPrice = newPrice;
    }

    function setMaxPerWallet(uint256 amount) external onlyOwner {
        require(amount > 0, "Zero amount");
        maxPerWallet = amount;
    }

    function setMaxPerTx(uint256 amount) external onlyOwner {
        require(amount > 0, "Zero amount");
        maxPerTx = amount;
    }

    function setBaseURI(string calldata uri) external onlyOwner {
        baseTokenURI = uri;
        emit BaseURISet(uri);
    }

    function setContractURI(string calldata uri) external onlyOwner {
        collectionContractURI = uri;
        emit ContractURISet(uri);
    }

    function setRoyaltyInfo(address receiver, uint96 feeNumerator) external onlyOwner {
        require(receiver != address(0), "Royalty zero address");
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    function withdrawAll(address payable to) external onlyOwner nonReentrant {
        _withdraw(to, address(this).balance);
    }

    function withdrawAmount(address payable to, uint256 amount) external onlyOwner nonReentrant {
        require(amount <= address(this).balance, "Insufficient balance");
        _withdraw(to, amount);
    }

    function _withdraw(address payable to, uint256 amount) internal {
        require(to != address(0), "Zero address");
        (bool ok, ) = to.call{value: amount}("");
        require(ok, "Withdraw failed");
        emit Withdraw(to, amount);
    }

    function _baseURI() internal view override returns (string memory) {
        return baseTokenURI;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "URI query for nonexistent token");
        return string(abi.encodePacked(baseTokenURI, _toString(tokenId), ".json"));
    }

    function contractURI() external view returns (string memory) {
        return collectionContractURI;
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
