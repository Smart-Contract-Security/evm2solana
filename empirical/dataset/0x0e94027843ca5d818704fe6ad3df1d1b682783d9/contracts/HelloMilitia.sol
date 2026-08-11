// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "erc721a/contracts/ERC721A.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";

struct MintQuote {
    uint256 totalPrice;
    bool isFreeMint;
    bool hasDiscount;
}

contract HelloMilitia is Ownable, ERC721A, ERC2981, Pausable, ReentrancyGuard {

    uint256 public constant INFANTRY_STRENGTH = 2222;
    uint256 private constant INFANTRY_RESERVE = 222;

    uint256 public immutable DEFAULT_MILITIA_PRICE;
    uint256 public constant DEPLOYMENT_CAP = 15;
    string private _baseTokenURI = "ipfs://bafybeifo3wb6ctw3lkdmy6t6ned5l2jahloqjmnjuafmplkokjbrf5zksa/";

    mapping(uint256 => uint256) private priceTiers;

    // Tier 1: first 222 militia holders — 1 free mint
    // Tier 2: next 222 militia holders — 1 50% off
    uint256 public constant MILADY_EARLYBIRD_SLOTS = 222;
    uint256 public constant MILADY_HALFOFF_SLOTS = 222;

    address public constant MILADY_COLLECTION = 0x5Af0D9827E0c53E4799BB226655A1de152A425a5;
    bool public militiaWhitelistActive;
    uint256 public miladyEarlyBirdClaimed;
    uint256 public miladyHalfOffClaimed;

    mapping(address => bool) private _miladyBenefitClaimed;

    event MilitiaMinted(address indexed to, uint256 quantity, uint256 totalPaid);
    event FundsWithdrawn(address indexed to, uint256 amount);
    event BaseURIUpdated(string newBaseURI);
    event MilitiaWhitelistStatusUpdated(bool active);
    event MilitiaEarlyBirdBenefitClaimed(address indexed account);
    event MiladyHalfOffBenefitClaimed(address indexed account);

    constructor() ERC721A("Militia March", "MILITIA") Ownable(msg.sender) {
        DEFAULT_MILITIA_PRICE = block.chainid == 1 ? 0.03 ether : 0.000000000003 ether;
        _setDefaultRoyalty(msg.sender, 700);
        _safeMint(msg.sender, INFANTRY_RESERVE);

          priceTiers[5] = DEFAULT_MILITIA_PRICE * 67 / 100;  // 33% off
          priceTiers[3] = DEFAULT_MILITIA_PRICE * 78 / 100;  // 22% off
    }

    function mintMilitia(address to, uint256 quantity) external payable whenNotPaused nonReentrant {
        require(quantity > 0, "You Cannot Draft Zero Soldiers...That Would Be Unethical");
        require(quantity <= DEPLOYMENT_CAP, "You Simply Cannot Mint This Many Tokens...Greed is a Cardinal Sin");
        require(_totalMinted() + quantity <= INFANTRY_STRENGTH, "There Are No More Soldiers Left To Draft...");

        uint256 priceOfFreedom = _tierPrice(quantity);
        uint256 totalCost = quantity * priceOfFreedom;

        if (
            militiaWhitelistActive &&
            _holdsMilady(msg.sender) &&
            !_miladyBenefitClaimed[msg.sender]
        ) {
            if (miladyEarlyBirdClaimed < MILADY_EARLYBIRD_SLOTS) {
                // Tier 1: one token is free
                _miladyBenefitClaimed[msg.sender] = true;
                miladyEarlyBirdClaimed++;
                totalCost = (quantity - 1) * priceOfFreedom;
                emit MilitiaEarlyBirdBenefitClaimed(msg.sender);
            } else if (miladyHalfOffClaimed < MILADY_HALFOFF_SLOTS) {
                // Tier 2: one token at half price
                _miladyBenefitClaimed[msg.sender] = true;
                miladyHalfOffClaimed++;
                totalCost = (quantity - 1) * priceOfFreedom + priceOfFreedom / 2;
                emit MiladyHalfOffBenefitClaimed(msg.sender);
            }
        }

        require(msg.value >= totalCost, "You Are Too Poor To Join The Militia...");

        _safeMint(to, quantity);
        emit MilitiaMinted(to, quantity, totalCost);

        uint256 excess = msg.value - totalCost;
        if (excess > 0) {
            (bool refunded, ) = msg.sender.call{value: excess}("");
            require(refunded, "Refund failed");
        }
    }

    function quoteMintPrice(uint256 quantity, address account) external view returns (MintQuote memory) {
        require(quantity > 0 && quantity <= DEPLOYMENT_CAP, "Invalid quantity");

        uint256 pricePerToken = _tierPrice(quantity);
        uint256 totalPrice = quantity * pricePerToken;
        bool isFreeMint = false;
        bool hasDiscount = false;

        if (
            militiaWhitelistActive &&
            account != address(0) &&
            !_miladyBenefitClaimed[account] &&
            _holdsMilady(account)
        ) {
            if (miladyEarlyBirdClaimed < MILADY_EARLYBIRD_SLOTS) {
                totalPrice = (quantity - 1) * pricePerToken;
                isFreeMint = true;
            } else if (miladyHalfOffClaimed < MILADY_HALFOFF_SLOTS) {
                totalPrice = (quantity - 1) * pricePerToken + pricePerToken / 2;
                hasDiscount = true;
            }
        }

        return MintQuote({ totalPrice: totalPrice, isFreeMint: isFreeMint, hasDiscount: hasDiscount });
    }

    function setRoyaltyInfo(address receiver, uint96 feeNumerator) external onlyOwner {
        require(receiver != address(0), "Invalid receiver address");
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    function setMilitiaWhitelistActive(bool active) external onlyOwner {
        militiaWhitelistActive = active;
        emit MilitiaWhitelistStatusUpdated(active);
    }

    function miladyBenefitClaimed(address account) external view returns (bool) {
        return _miladyBenefitClaimed[account];
    }

    function militiaTierSlotsRemaining() external view returns (uint256 earlyBird, uint256 halfOff) {
        earlyBird = MILADY_EARLYBIRD_SLOTS - miladyEarlyBirdClaimed;
        halfOff = MILADY_HALFOFF_SLOTS - miladyHalfOffClaimed;
    }

    function canMintWithMilady(address account) external view returns (bool) {
        if (!militiaWhitelistActive) return true;
        return _holdsMilady(account);
    }

    function _tierPrice(uint256 quantity) internal view returns (uint256) {
        if (quantity >= 5) return priceTiers[5];
        if (quantity >= 3) return priceTiers[3];
        return DEFAULT_MILITIA_PRICE;
    }

    function _holdsMilady(address account) internal view returns (bool) {
        (bool success, bytes memory data) = MILADY_COLLECTION.staticcall(
            abi.encodeWithSelector(IERC721.balanceOf.selector, account)
        );
        if (!success || data.length < 32) return false;
        return abi.decode(data, (uint256)) > 0;
    }

    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (!_exists(tokenId)) revert URIQueryForNonexistentToken();
        string memory base = _baseURI();
        return bytes(base).length != 0
            ? string(abi.encodePacked(base, _toString(tokenId), ".json"))
            : "";
    }

    function withdraw() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No Funds To Withdraw");
        (bool success, ) = msg.sender.call{value: balance}("");
        require(success, "Transfer Failed");
        emit FundsWithdrawn(msg.sender, balance);
    }

    function setBaseURI(string calldata baseURI) external onlyOwner {
        _baseTokenURI = baseURI;
        emit BaseURIUpdated(baseURI);
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721A, ERC2981) returns (bool) {
        return ERC721A.supportsInterface(interfaceId) || ERC2981.supportsInterface(interfaceId);
    }

    function paws() public onlyOwner {
        _pause();
    }

    function unpaws() public onlyOwner {
        _unpause();
    }
}