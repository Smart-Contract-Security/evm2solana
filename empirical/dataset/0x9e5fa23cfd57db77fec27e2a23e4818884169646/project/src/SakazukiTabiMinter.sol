// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "./SakazukiTabi.sol";

contract SakazukiTabiMinter is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");

    struct SaleConfig {
        uint256 priceJPY;
        uint256 maxSupply;
        uint256 sold;
        bool isActive;
        bool isSet;
    }

    SakazukiTabi public nftContract;
    IERC721 public collectiveContract;
    AggregatorV3Interface public ethUsdPriceFeed;
    AggregatorV3Interface public jpyUsdPriceFeed;
    IERC20 public usdcToken;

    mapping(uint8 => SaleConfig) private _saleConfig;

    event SaleActiveChanged(uint8 indexed typeId, bool active);
    event SaleConfigUpdated(uint8 indexed typeId, uint256 priceJPY, uint256 maxSupply);
    event PriceUpdated(uint8 indexed typeId, uint256 priceJPY);
    event MaxSupplyUpdated(uint8 indexed typeId, uint256 maxSupply);
    event NftContractUpdated(address indexed newNft);
    event CollectiveContractUpdated(address indexed newCollective);
    event EthUsdPriceFeedUpdated(address indexed newPriceFeed);
    event JpyUsdPriceFeedUpdated(address indexed newPriceFeed);
    event UsdcTokenUpdated(address indexed newUsdcToken);

    event Purchased(
        address indexed buyer,
        uint8 indexed typeId,
        uint256 quantity,
        uint256 totalPrice
    );
    event PurchasedUSDC(
        address indexed buyer,
        uint8 indexed typeId,
        uint256 quantity,
        uint256 totalPrice
    );
    event AgentMintPrepaid(
        address indexed to,
        uint8 indexed typeId,
        uint256 quantity
    );
    event OwnerMint(address indexed to, uint8 indexed typeId, uint256 quantity);
    event Withdrawn(address indexed recipient, uint256 amount);
    event WithdrawnUSDC(address indexed recipient, uint256 amount);

    error SaleClosed();
    error InvalidAddress();
    error InvalidQuantity();
    error InvalidMaxSupply();
    error SaleConfigNotSet();
    error NotCollectiveHolder();
    error SoldOut();
    error InsufficientPayment();
    error WithdrawFailed();
    error InvalidPriceFeed();
    error StalePriceData();

    constructor(
        address nftContract_,
        address collectiveContract_,
        address ethUsdPriceFeed_,
        address jpyUsdPriceFeed_,
        address usdcToken_
    ) {
        if (
            nftContract_ == address(0) ||
            collectiveContract_ == address(0) ||
            ethUsdPriceFeed_ == address(0) ||
            jpyUsdPriceFeed_ == address(0) ||
            usdcToken_ == address(0)
        ) {
            revert InvalidAddress();
        }

        nftContract = SakazukiTabi(nftContract_);
        collectiveContract = IERC721(collectiveContract_);
        ethUsdPriceFeed = AggregatorV3Interface(ethUsdPriceFeed_);
        jpyUsdPriceFeed = AggregatorV3Interface(jpyUsdPriceFeed_);
        usdcToken = IERC20(usdcToken_);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // ========= Purchase (ETH) =========

    function buy(
        uint8 typeId,
        uint256 quantity
    ) external payable nonReentrant {
        _requireValidQuantity(quantity);
        _requireCollectiveHolder(msg.sender);

        SaleConfig storage cfg = _saleConfig[typeId];
        if (!cfg.isSet) revert SaleConfigNotSet();
        if (!cfg.isActive) revert SaleClosed();
        if (cfg.sold + quantity > cfg.maxSupply) revert SoldOut();

        uint256 pricePerToken = _getEthPriceFromJpy(cfg.priceJPY);
        uint256 totalPrice = pricePerToken * quantity;
        if (msg.value < totalPrice) revert InsufficientPayment();

        cfg.sold += quantity;
        _mintMultiple(msg.sender, typeId, quantity);

        emit Purchased(msg.sender, typeId, quantity, totalPrice);

        if (msg.value > totalPrice) {
            (bool success, ) = msg.sender.call{value: msg.value - totalPrice}("");
            require(success, "Refund failed");
        }
    }

    // ========= Purchase (USDC) =========

    function buyUSDC(
        uint8 typeId,
        uint256 quantity
    ) external nonReentrant {
        _requireValidQuantity(quantity);
        _requireCollectiveHolder(msg.sender);

        SaleConfig storage cfg = _saleConfig[typeId];
        if (!cfg.isSet) revert SaleConfigNotSet();
        if (!cfg.isActive) revert SaleClosed();
        if (cfg.sold + quantity > cfg.maxSupply) revert SoldOut();

        uint256 jpyUsdPrice = _getLatestJpyUsdPrice();
        uint256 pricePerTokenUSDC = (cfg.priceJPY * jpyUsdPrice + 5e19) / 1e20;
        uint256 totalPrice = pricePerTokenUSDC * quantity;

        usdcToken.safeTransferFrom(msg.sender, address(this), totalPrice);

        cfg.sold += quantity;
        _mintMultiple(msg.sender, typeId, quantity);

        emit PurchasedUSDC(msg.sender, typeId, quantity, totalPrice);
    }

    // ========= Agent Prepaid Mint (credit card backend) =========

    function agentMintPrepaid(
        address to,
        uint8 typeId,
        uint256 quantity
    ) external onlyRole(AGENT_ROLE) nonReentrant {
        _requireValidQuantity(quantity);
        if (to == address(0)) revert InvalidAddress();
        _requireCollectiveHolder(to);

        SaleConfig storage cfg = _saleConfig[typeId];
        if (!cfg.isSet) revert SaleConfigNotSet();
        if (!cfg.isActive) revert SaleClosed();
        if (cfg.sold + quantity > cfg.maxSupply) revert SoldOut();

        cfg.sold += quantity;
        _mintMultiple(to, typeId, quantity);

        emit AgentMintPrepaid(to, typeId, quantity);
    }

    // ========= Owner Mint (no holder check, no cap) =========

    function ownerMint(
        address to,
        uint8 typeId,
        uint256 quantity
    ) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        if (to == address(0)) revert InvalidAddress();
        _requireValidQuantity(quantity);

        _mintMultiple(to, typeId, quantity);
        emit OwnerMint(to, typeId, quantity);
    }

    // ========= Admin: sale config =========

    function setSaleConfig(
        uint8 typeId,
        uint256 priceJPY,
        uint256 maxSupply
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        SaleConfig storage cfg = _saleConfig[typeId];
        if (maxSupply < cfg.sold) revert InvalidMaxSupply();

        cfg.priceJPY = priceJPY;
        cfg.maxSupply = maxSupply;
        cfg.isSet = true;

        emit SaleConfigUpdated(typeId, priceJPY, maxSupply);
    }

    function setPriceJPY(
        uint8 typeId,
        uint256 priceJPY
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        SaleConfig storage cfg = _saleConfig[typeId];
        if (!cfg.isSet) revert SaleConfigNotSet();
        cfg.priceJPY = priceJPY;
        emit PriceUpdated(typeId, priceJPY);
    }

    function setMaxSupply(
        uint8 typeId,
        uint256 maxSupply
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        SaleConfig storage cfg = _saleConfig[typeId];
        if (!cfg.isSet) revert SaleConfigNotSet();
        if (maxSupply < cfg.sold) revert InvalidMaxSupply();
        cfg.maxSupply = maxSupply;
        emit MaxSupplyUpdated(typeId, maxSupply);
    }

    function setSaleActive(
        uint8 typeId,
        bool active
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        SaleConfig storage cfg = _saleConfig[typeId];
        if (!cfg.isSet) revert SaleConfigNotSet();
        cfg.isActive = active;
        emit SaleActiveChanged(typeId, active);
    }

    // ========= Admin: dependencies =========

    function setNftContract(
        address newNft
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newNft == address(0)) revert InvalidAddress();
        nftContract = SakazukiTabi(newNft);
        emit NftContractUpdated(newNft);
    }

    function setCollectiveContract(
        address newCollective
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newCollective == address(0)) revert InvalidAddress();
        collectiveContract = IERC721(newCollective);
        emit CollectiveContractUpdated(newCollective);
    }

    function setEthUsdPriceFeed(
        address newPriceFeed
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newPriceFeed == address(0)) revert InvalidAddress();
        ethUsdPriceFeed = AggregatorV3Interface(newPriceFeed);
        emit EthUsdPriceFeedUpdated(newPriceFeed);
    }

    function setJpyUsdPriceFeed(
        address newPriceFeed
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newPriceFeed == address(0)) revert InvalidAddress();
        jpyUsdPriceFeed = AggregatorV3Interface(newPriceFeed);
        emit JpyUsdPriceFeedUpdated(newPriceFeed);
    }

    function setUsdcToken(
        address newUsdcToken
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newUsdcToken == address(0)) revert InvalidAddress();
        usdcToken = IERC20(newUsdcToken);
        emit UsdcTokenUpdated(newUsdcToken);
    }

    // ========= Withdraw =========

    function withdraw(
        address payable recipient
    ) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        if (recipient == address(0)) revert InvalidAddress();
        uint256 balance = address(this).balance;
        (bool success, ) = recipient.call{value: balance}("");
        if (!success) revert WithdrawFailed();
        emit Withdrawn(recipient, balance);
    }

    function withdrawUSDC(
        address recipient
    ) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        if (recipient == address(0)) revert InvalidAddress();
        uint256 balance = usdcToken.balanceOf(address(this));
        usdcToken.safeTransfer(recipient, balance);
        emit WithdrawnUSDC(recipient, balance);
    }

    // ========= Views =========

    function getSaleConfig(
        uint8 typeId
    )
        external
        view
        returns (
            uint256 priceJPY,
            uint256 maxSupply,
            uint256 sold,
            bool isActive,
            bool isSet
        )
    {
        SaleConfig memory cfg = _saleConfig[typeId];
        return (cfg.priceJPY, cfg.maxSupply, cfg.sold, cfg.isActive, cfg.isSet);
    }

    function getRemainingSupply(
        uint8 typeId
    ) external view returns (uint256) {
        SaleConfig memory cfg = _saleConfig[typeId];
        if (!cfg.isSet || cfg.sold >= cfg.maxSupply) return 0;
        return cfg.maxSupply - cfg.sold;
    }

    function getEthPriceFor(
        uint8 typeId
    ) external view returns (uint256) {
        SaleConfig memory cfg = _saleConfig[typeId];
        if (!cfg.isSet) revert SaleConfigNotSet();
        return _getEthPriceFromJpy(cfg.priceJPY);
    }

    function getUsdcPriceFor(
        uint8 typeId
    ) external view returns (uint256) {
        SaleConfig memory cfg = _saleConfig[typeId];
        if (!cfg.isSet) revert SaleConfigNotSet();
        uint256 jpyUsdPrice = _getLatestJpyUsdPrice();
        return (cfg.priceJPY * jpyUsdPrice + 5e19) / 1e20;
    }

    function getLatestEthUsdPrice() external view returns (uint256) {
        return _getLatestEthUsdPrice();
    }

    function getLatestJpyUsdPrice() external view returns (uint256) {
        return _getLatestJpyUsdPrice();
    }

    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    // ========= Internals =========

    function _requireValidQuantity(uint256 quantity) internal pure {
        if (quantity == 0) revert InvalidQuantity();
    }

    function _requireCollectiveHolder(address account) internal view {
        if (collectiveContract.balanceOf(account) == 0) revert NotCollectiveHolder();
    }

    function _mintMultiple(
        address to,
        uint8 typeId,
        uint256 quantity
    ) internal {
        for (uint256 i = 0; i < quantity; i++) {
            nftContract.mint(to, typeId);
        }
    }

    function _getLatestEthUsdPrice() internal view returns (uint256) {
        (
            uint80 roundId,
            int256 price,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = ethUsdPriceFeed.latestRoundData();

        if (price <= 0) revert InvalidPriceFeed();
        if (updatedAt == 0) revert InvalidPriceFeed();
        if (answeredInRound < roundId) revert StalePriceData();
        if (block.timestamp - updatedAt > 24 hours) revert StalePriceData();

        return uint256(price);
    }

    function _getLatestJpyUsdPrice() internal view returns (uint256) {
        (
            uint80 roundId,
            int256 price,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = jpyUsdPriceFeed.latestRoundData();

        if (price <= 0) revert InvalidPriceFeed();
        if (updatedAt == 0) revert InvalidPriceFeed();
        if (answeredInRound < roundId) revert StalePriceData();
        if (block.timestamp - updatedAt > 24 hours) revert StalePriceData();

        return uint256(price);
    }

    function _getEthPriceFromJpy(
        uint256 jpyAmount
    ) internal view returns (uint256) {
        uint256 ethUsdPrice = _getLatestEthUsdPrice();
        uint256 jpyUsdPrice = _getLatestJpyUsdPrice();
        return (jpyAmount * jpyUsdPrice) / ethUsdPrice;
    }
}
