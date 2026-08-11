// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface AggregatorV3Interface {
    function decimals() external view returns (uint8);

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

contract SatoshyPresale is Ownable2Step, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 private constant USD_PRECISION = 1e18;
    uint256 private constant SATO_PRECISION = 1e18;

    address public treasury;

    uint256 public pricePerSato;

    AggregatorV3Interface public nativeUsdFeed;

    uint256 public maxPriceAge;

    mapping(address => bool) public acceptedToken;

    uint256 public minNative;
    uint256 public maxNative;

    mapping(address => uint256) public minToken;
    mapping(address => uint256) public maxToken;

    mapping(address => uint256) public satoAllocated;

    event PurchaseMade(
        address indexed buyer,
        address indexed paymentToken,
        uint256 paymentAmount,
        uint256 satoAmount,
        uint256 pricePerSato,
        address treasury,
        uint256 timestamp
    );
    event PriceUpdated(uint256 previousPrice, uint256 newPrice);
    event TreasuryUpdated(address indexed previousTreasury, address indexed newTreasury);
    event NativeUsdFeedUpdated(address indexed previousFeed, address indexed newFeed);
    event MaxPriceAgeUpdated(uint256 previousAge, uint256 newAge);
    event AcceptedTokenUpdated(address indexed token, bool accepted);
    event NativeLimitsUpdated(uint256 minNative, uint256 maxNative);
    event TokenLimitsUpdated(address indexed token, uint256 minToken, uint256 maxToken);
    event RescuedNative(address indexed to, uint256 amount);
    event RescuedERC20(address indexed token, address indexed to, uint256 amount);

    error ZeroAddress();
    error ZeroAmount();
    error ZeroPrice();
    error TokenNotAccepted(address token);
    error BelowMinimum(uint256 amount, uint256 min);
    error AboveMaximum(uint256 amount, uint256 max);
    error NativeTransferFailed();
    error InvalidLimits(uint256 min, uint256 max);
    error StalePrice();
    error InvalidPriceFeed();
    error InvalidDecimals();
    error NothingAllocated();

    constructor(
        address initialOwner,
        address initialTreasury,
        address usdtToken,
        address feed,
        uint256 initialPricePerSato
    ) Ownable(initialOwner) {
        if (
            initialTreasury == address(0) ||
            usdtToken == address(0) ||
            feed == address(0)
        ) revert ZeroAddress();
        if (initialPricePerSato == 0) revert ZeroPrice();

        treasury = initialTreasury;
        emit TreasuryUpdated(address(0), initialTreasury);

        acceptedToken[usdtToken] = true;
        emit AcceptedTokenUpdated(usdtToken, true);

        nativeUsdFeed = AggregatorV3Interface(feed);
        emit NativeUsdFeedUpdated(address(0), feed);

        pricePerSato = initialPricePerSato;
        emit PriceUpdated(0, initialPricePerSato);

        maxPriceAge = 3600;
        emit MaxPriceAgeUpdated(0, 3600);
    }

    function buySato() external payable {
        _buyWithNative();
    }

    receive() external payable {
        _buyWithNative();
    }

    function buySato(address token, uint256 amount) external nonReentrant whenNotPaused {
        if (token == address(0)) revert ZeroAddress();
        if (!acceptedToken[token]) revert TokenNotAccepted(token);
        if (amount == 0) revert ZeroAmount();

        uint256 minA = minToken[token];
        uint256 maxA = maxToken[token];
        if (minA != 0 && amount < minA) revert BelowMinimum(amount, minA);
        if (maxA != 0 && amount > maxA) revert AboveMaximum(amount, maxA);

        uint8 tokenDecimals = IERC20Metadata(token).decimals();
        if (tokenDecimals > 36) revert InvalidDecimals();
        uint256 usdValue = Math.mulDiv(amount, USD_PRECISION, 10 ** tokenDecimals);
        uint256 satoAmount = _satoForUsd(usdValue);

        satoAllocated[msg.sender] += satoAmount;

        address dest = treasury;
        IERC20(token).safeTransferFrom(msg.sender, dest, amount);

        emit PurchaseMade(msg.sender, token, amount, satoAmount, pricePerSato, dest, block.timestamp);
    }

    function _buyWithNative() private nonReentrant whenNotPaused {
        uint256 amount = msg.value;
        if (amount == 0) revert ZeroAmount();
        if (minNative != 0 && amount < minNative) revert BelowMinimum(amount, minNative);
        if (maxNative != 0 && amount > maxNative) revert AboveMaximum(amount, maxNative);

        uint256 usdValue = _nativeToUsd(amount);
        uint256 satoAmount = _satoForUsd(usdValue);

        satoAllocated[msg.sender] += satoAmount;

        address dest = treasury;
        (bool ok, ) = dest.call{value: amount}("");
        if (!ok) revert NativeTransferFailed();

        emit PurchaseMade(msg.sender, address(0), amount, satoAmount, pricePerSato, dest, block.timestamp);
    }

    function nativeUsdPrice() public view returns (uint256) {
        (uint80 roundId, int256 answer, , uint256 updatedAt, uint80 answeredInRound) =
            nativeUsdFeed.latestRoundData();
        if (answer <= 0 || updatedAt == 0 || answeredInRound < roundId) revert InvalidPriceFeed();
        if (block.timestamp - updatedAt > maxPriceAge) revert StalePrice();
        uint8 feedDecimals = nativeUsdFeed.decimals();
        if (feedDecimals > 36) revert InvalidDecimals();
        return Math.mulDiv(uint256(answer), USD_PRECISION, 10 ** feedDecimals);
    }

    function quoteNative(uint256 nativeAmount) external view returns (uint256) {
        return _satoForUsd(_nativeToUsd(nativeAmount));
    }

    function quoteToken(address token, uint256 amount) external view returns (uint256) {
        if (!acceptedToken[token]) revert TokenNotAccepted(token);
        uint8 tokenDecimals = IERC20Metadata(token).decimals();
        if (tokenDecimals > 36) revert InvalidDecimals();
        return _satoForUsd(Math.mulDiv(amount, USD_PRECISION, 10 ** tokenDecimals));
    }

    function _nativeToUsd(uint256 nativeAmount) private view returns (uint256) {
        return Math.mulDiv(nativeAmount, nativeUsdPrice(), USD_PRECISION);
    }

    function _satoForUsd(uint256 usdValue) private view returns (uint256) {
        uint256 satoAmount = Math.mulDiv(usdValue, SATO_PRECISION, pricePerSato);
        if (satoAmount == 0) revert NothingAllocated();
        return satoAmount;
    }

    function setPrice(uint256 newPricePerSato) external onlyOwner {
        if (newPricePerSato == 0) revert ZeroPrice();
        uint256 previous = pricePerSato;
        pricePerSato = newPricePerSato;
        emit PriceUpdated(previous, newPricePerSato);
    }

    function setTreasury(address newTreasury) external onlyOwner {
        if (newTreasury == address(0)) revert ZeroAddress();
        address previous = treasury;
        treasury = newTreasury;
        emit TreasuryUpdated(previous, newTreasury);
    }

    function setNativeUsdFeed(address feed) external onlyOwner {
        if (feed == address(0)) revert ZeroAddress();
        address previous = address(nativeUsdFeed);
        nativeUsdFeed = AggregatorV3Interface(feed);
        emit NativeUsdFeedUpdated(previous, feed);
    }

    function setMaxPriceAge(uint256 newMaxPriceAge) external onlyOwner {
        if (newMaxPriceAge == 0) revert ZeroAmount();
        uint256 previous = maxPriceAge;
        maxPriceAge = newMaxPriceAge;
        emit MaxPriceAgeUpdated(previous, newMaxPriceAge);
    }

    function setAcceptedToken(address token, bool accepted) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        acceptedToken[token] = accepted;
        emit AcceptedTokenUpdated(token, accepted);
    }

    function setNativeLimits(uint256 newMinNative, uint256 newMaxNative) external onlyOwner {
        if (newMinNative != 0 && newMaxNative != 0 && newMinNative > newMaxNative) {
            revert InvalidLimits(newMinNative, newMaxNative);
        }
        minNative = newMinNative;
        maxNative = newMaxNative;
        emit NativeLimitsUpdated(newMinNative, newMaxNative);
    }

    function setTokenLimits(address token, uint256 newMinToken, uint256 newMaxToken) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        if (newMinToken != 0 && newMaxToken != 0 && newMinToken > newMaxToken) {
            revert InvalidLimits(newMinToken, newMaxToken);
        }
        minToken[token] = newMinToken;
        maxToken[token] = newMaxToken;
        emit TokenLimitsUpdated(token, newMinToken, newMaxToken);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function rescueNative(address to, uint256 amount) external onlyOwner nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        (bool ok, ) = to.call{value: amount}("");
        if (!ok) revert NativeTransferFailed();
        emit RescuedNative(to, amount);
    }

    function rescueERC20(address token, address to, uint256 amount) external onlyOwner nonReentrant {
        if (token == address(0) || to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        IERC20(token).safeTransfer(to, amount);
        emit RescuedERC20(token, to, amount);
    }
}
