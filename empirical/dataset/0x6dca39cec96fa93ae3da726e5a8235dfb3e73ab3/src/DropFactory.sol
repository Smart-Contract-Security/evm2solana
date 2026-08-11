// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./MonthlyDropNFT.sol";

contract DropFactory is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    uint256 public annualMintLimit;
    uint256 public annualMintCount;

    struct DropInfo {
        string dropName;
        uint256 mintLimit;
        uint256 price;
        address dropAddress;
        uint256 startTimestamp;
    }

    mapping(uint256 => DropInfo) public drops;
    mapping(address => bool) public isAdmin;

    uint256 public dropCount;

    event DropCreated(uint256 indexed dropId, address dropAddress);
    event AdminUpdated(address indexed admin, bool enabled);
    event MintCountUpdated(uint256 newTotal);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    modifier onlyAdmin() {
        require(isAdmin[msg.sender], "Not an admin");
        _;
    }
    function initialize() public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();

        annualMintLimit = 10_000;
        isAdmin[msg.sender] = true;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function isHolderofAny(address user) external view returns (bool) {
        for (uint256 i = 0; i < dropCount; ) {
            if (
                MonthlyDropNFT(payable(drops[i].dropAddress)).balanceOf(user) >
                0
            ) {
                return true;
            }
            unchecked {
                ++i;
            }
        }
        return false;
    }

    function setAdmin(address user, bool enabled) external onlyOwner {
        isAdmin[user] = enabled;
        emit AdminUpdated(user, enabled);
    }

    function createDrop(
        string memory dropName,
        uint256 mintLimit,
        uint256 price,
        string memory baseURI,
        uint256 startTimestamp
    ) external onlyOwner {
        MonthlyDropNFT newDrop = new MonthlyDropNFT(
            dropName,
            mintLimit,
            price,
            address(this),
            baseURI,
            startTimestamp
        );

        drops[dropCount] = DropInfo({
            dropName: dropName,
            mintLimit: mintLimit,
            price: price,
            dropAddress: address(newDrop),
            startTimestamp: startTimestamp
        });
        emit DropCreated(dropCount, address(newDrop));
        dropCount++;
    }

    function getAllDrops() external view returns (DropInfo[] memory) {
        DropInfo[] memory allDrops = new DropInfo[](dropCount);
        for (uint256 i = 0; i < dropCount; ) {
            allDrops[i] = drops[i];
            unchecked {
                ++i;
            }
        }
        return allDrops;
    }

    modifier onlyChild() {
        for (uint256 i = 0; i < dropCount; ) {
            if (drops[i].dropAddress == msg.sender) {
                _;
                return;
            }
            unchecked {
                ++i;
            }
        }
        revert("Caller is not a valid drop contract");
    }

    function updateMintCount(uint256 amount) external onlyChild {
        annualMintCount = annualMintCount + amount;
        emit MintCountUpdated(annualMintCount);
    }

    function withdraw(address to, address dropNFT) external onlyAdmin {
        MonthlyDropNFT(payable(dropNFT)).withdraw(to);
    }

    function setBaseURI(
        address dropNFT,
        string memory newBaseURI
    ) external onlyOwner {
        MonthlyDropNFT(payable(dropNFT)).setBaseURI(newBaseURI);
    }
}
