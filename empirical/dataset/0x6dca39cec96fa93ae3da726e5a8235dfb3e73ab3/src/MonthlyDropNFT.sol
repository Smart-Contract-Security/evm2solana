// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IDropFactory {
    function isHolderofAny(address user) external view returns (bool);
    function isAdmin(address user) external view returns (bool);
    function annualMintLimit() external view returns (uint256);
    function annualMintCount() external view returns (uint256);
    function updateMintCount(uint256 amount) external;
}

contract MonthlyDropNFT is ERC721, ERC2981, Ownable, ReentrancyGuard {
    uint256 private _tokenIdTracker;

    uint256 public immutable mintLimit;
    uint256 public immutable price;
    uint256 public immutable startTimestamp;
    address public COMPANY_ADDRESS = 0xC494d102199917b703cf1DbBf5d488D0f95D2239;
    string private _baseTokenURI;

    address public immutable factory;

    mapping(uint256 => uint256) public tokenFirstHeldAt;
    mapping(uint256 => address) public firstOwner;

    event RoyaltySplit(
        address indexed to,
        uint256 holderShare,
        uint256 companyShare
    );
    event Withdrawn(address indexed to, uint256 amount);

    constructor(
        string memory name,
        uint256 _mintLimit,
        uint256 _price,
        address _factory,
        string memory _tokenURI,
        uint256 _startTimestamp
    ) ERC721(name, "DROP") ERC2981() Ownable(msg.sender) {
        require(_factory != address(0), "Invalid factory");
        require(_startTimestamp > 0, "Invalid timestamp");

        mintLimit = _mintLimit;
        price = _price;
        factory = _factory;
        startTimestamp = _startTimestamp;
        _baseTokenURI = _tokenURI;

        _setDefaultRoyalty(address(this), 1000); // 1000 = 10%
    }

    // Receive function
    receive() external payable {}

    modifier onlyStartedOrEarlyAccess() {
        //prevent minting if more than 30 days have passed
        require(
            block.timestamp <= startTimestamp + 30 days,
            "Minting period is over"
        );

        if (block.timestamp < startTimestamp) {
            // We're before the official start — allow only holders
            require(
                IDropFactory(factory).isHolderofAny(msg.sender),
                "Only holders can mint before start"
            );
            require(
                block.timestamp >= startTimestamp - 3 days,
                "Too early for early access"
            );
        }
        // Else: we're past startTimestamp, anyone can mint
        _;
    }

    modifier onlyAdmin() {
        require(IDropFactory(factory).isAdmin(msg.sender), "Not an admin");
        _;
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function setBaseURI(string memory newBaseUrl) external onlyOwner {
        _baseTokenURI = newBaseUrl;
    }

    function mint(
        uint256 quantity
    ) external payable onlyStartedOrEarlyAccess nonReentrant {
        require(
            _tokenIdTracker + quantity <= mintLimit,
            "All NFTs are sold out"
        );
        require(
            IDropFactory(factory).annualMintCount() + quantity <=
                IDropFactory(factory).annualMintLimit(),
            "Annual mint limit exceeded"
        );
        require(msg.value >= price * quantity, "Insufficient ETH");
        for (uint256 i = 0; i < quantity; ) {
            uint256 tokenId = _tokenIdTracker++;
            _safeMint(msg.sender, tokenId);
            tokenFirstHeldAt[tokenId] = block.timestamp;
            firstOwner[tokenId] = msg.sender;
            unchecked {
                ++i;
            }
        }
        payable(COMPANY_ADDRESS).transfer(msg.value);
        IDropFactory(factory).updateMintCount(quantity);
    }

    function royaltyInfo(
        uint256, // tokenId
        uint256 salePrice
    ) public view override returns (address, uint256) {
        return super.royaltyInfo(0, salePrice); // fallback to default royalty
    }

    function totalSupply() public view returns (uint256) {
        return _tokenIdTracker;
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721, ERC2981) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function withdraw(address to) external onlyOwner nonReentrant {
        uint256 amount = address(this).balance;
        require(amount > 0, "No balance to withdraw");
        emit Withdrawn(to, amount);
        payable(to).transfer(amount);
    }

    // Split royalty after each sale
    function splitRoyalty(
        uint256 tokenId,
        uint256 salePrice
    ) external onlyAdmin nonReentrant {
        address firstHolder = firstOwner[tokenId];
        require(firstHolder != address(0), "No first holder");

        uint256 royaltyAmount = (salePrice * 10) / 100; // 10% royalty
        require(royaltyAmount <= address(this).balance, "Insufficient ETH");
        uint256 holderShare;
        uint256 companyShare;

        uint256 durationHeld = block.timestamp - tokenFirstHeldAt[tokenId];
        uint256 bips = durationHeld < 180 days
            ? 200
            : (durationHeld < 365 days ? 300 : 400); // 2% / 3% / 4%

        // Calculate the holder's share
        holderShare = (royaltyAmount * bips) / 10000;
        companyShare = royaltyAmount - holderShare;

        // Send the royalty
        payable(firstHolder).transfer(holderShare);
        payable(COMPANY_ADDRESS).transfer(companyShare); // Send company share to owner
        emit RoyaltySplit(firstHolder, holderShare, companyShare);
    }
}
