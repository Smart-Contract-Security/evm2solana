// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {OwnableUpgradeable as Ownable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IERC20Upgradeable as IERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {ERC20Upgradeable as ERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {SafeERC20Upgradeable as SafeERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "./libraries/DecimalsCorrectionLibrary.sol";

contract TokenSale is Ownable {
    using SafeERC20 for IERC20;
    using DecimalsCorrectionLibrary for uint256;

    mapping(string => uint256) public tokenBalances;
    mapping(uint256 => uint256) public roundPrice;
    mapping(uint256 => bool) public isRoundInProgress;

    address public adminAddress;
    address public ethUsdPriceFeed;
    address public usdtUsdPriceFeed;
    address public usdtAddress;

    uint256 public currentRound;
    uint256 public currentRoundEndTime;
    uint256 public minUsdThreshold;
    uint256 public totalTokenSold;
    uint256 public maxTokenToSell;
    uint256 public totalUsdAmount;

    event Buy(
        bytes tokenUserAddress,
        bytes referrer,
        uint256 amount,
        uint256 usdAmount,
        uint256 roundId
    );

    error InsufficientUsdAmount(uint256 transfered, uint256 requiredMinimum);
    error RoundIsNotInProgress();
    error ExceededTokenMaxAmount();
    error ZeroRoundPrice();

    uint256[50] private __gap;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _adminAddress,
        address _ethUsdPriceFeed,
        address _usdtUsdPriceFeed,
        address _usdtAddress,
        uint256 _minUsdThreshold
    ) external initializer {
        __Ownable_init();
        adminAddress = _adminAddress;
        ethUsdPriceFeed = _ethUsdPriceFeed;
        usdtUsdPriceFeed = _usdtUsdPriceFeed;
        usdtAddress = _usdtAddress;
        minUsdThreshold = _minUsdThreshold;
    }

    function manageAdminAddress(address _newAdminAddress) external onlyOwner {
        adminAddress = _newAdminAddress;
    }

    function manageEthUsdPriceFeed(
        address _newEthUsdPriceFeed
    ) external onlyOwner {
        ethUsdPriceFeed = _newEthUsdPriceFeed;
    }

    function manageUsdtUsdPriceFeed(
        address _newUsdtUsdPriceFeed
    ) external onlyOwner {
        usdtUsdPriceFeed = _newUsdtUsdPriceFeed;
    }

    function manageUsdtAddress(address _newUsdtAddress) external onlyOwner {
        usdtAddress = _newUsdtAddress;
    }

    function manageMinUsdThreshold(
        uint256 _newUsdThreshold
    ) external onlyOwner {
        minUsdThreshold = _newUsdThreshold;
    }

    function manageMaxTokenToSell(uint256 _newAmount) external onlyOwner {
        maxTokenToSell = _newAmount;
    }

    function newRound(
        uint256 _newRoundPrice,
        uint256 _roundEndTime,
        uint256 _newMaxTokens
    ) external onlyOwner {
        if (_newRoundPrice == 0) revert ZeroRoundPrice();

        currentRound++;
        maxTokenToSell = _newMaxTokens;
        roundPrice[currentRound] = _newRoundPrice;
        currentRoundEndTime = _roundEndTime;
        isRoundInProgress[currentRound] = true;
    }

    function stopRound() external onlyOwner isCurrentRoundInProgress {
        isRoundInProgress[currentRound] = false;
    }

    function buyTokens(
        string memory _userTokenAddress,
        string memory _referer,
        uint256 _usdtAmount
    ) external isCurrentRoundInProgress {
        uint256 formatDigits = _usdtAmount.convertFromBase18(
            ERC20(usdtAddress).decimals()
        );

        IERC20(usdtAddress).safeTransferFrom(
            msg.sender,
            address(this),
            formatDigits
        );

        _buy(_userTokenAddress, usdtUsdPriceFeed, _referer, _usdtAmount);
    }

    function buyTokens(
        string memory _userTokenAddress,
        string memory _referer
    ) external payable isCurrentRoundInProgress {
        _buy(_userTokenAddress, ethUsdPriceFeed, _referer, msg.value);
    }

    function withdrawOwner(uint256 _usdAmount, bool _inEth) external onlyOwner {
        _withdraw(_usdAmount, _inEth, adminAddress);
    }

    function viewUserBalance(
        string memory _address
    ) external view returns (uint256) {
        return tokenBalances[_address];
    }

    function getCurrency(address _priceFeed) public view returns (uint256) {
        AggregatorV3Interface localDataFeed = AggregatorV3Interface(_priceFeed);
        (, int256 currency, , , ) = localDataFeed.latestRoundData();

        uint8 decimals = localDataFeed.decimals();

        uint256 parsedCurrency = uint256(currency).convertToBase18(
            uint256(decimals)
        );

        return parsedCurrency;
    }

    function _buy(
        string memory _userTokenAddress,
        address _priceFeed,
        string memory _referer,
        uint256 _amount
    ) internal returns (uint256) {
        uint256 currency = getCurrency(_priceFeed);

        uint256 usdAmount = (currency * _amount) / 10 ** 18;

        if (usdAmount < minUsdThreshold)
            revert InsufficientUsdAmount({
                transfered: usdAmount,
                requiredMinimum: minUsdThreshold
            });

        uint256 tokenAmount = (usdAmount * 10 ** 18) / roundPrice[currentRound];

        if (totalTokenSold + tokenAmount > maxTokenToSell)
            revert ExceededTokenMaxAmount();

        totalUsdAmount += usdAmount;

        totalTokenSold += tokenAmount;

        tokenBalances[_userTokenAddress] += tokenAmount;

        bytes memory encodedStr = abi.encode(_userTokenAddress);
        bytes memory encodedReferer = abi.encode(_referer);

        emit Buy(
            encodedStr,
            encodedReferer,
            tokenAmount,
            usdAmount,
            currentRound
        );

        return tokenAmount;
    }

    function _withdraw(
        uint256 _tokenAmount,
        bool _inEth,
        address _recipient
    ) private {
        uint256 expectedTransferInUsdt;
        if (_inEth) {
            payable(_recipient).transfer(_tokenAmount);
        } else {
            address _usdtAddress = usdtAddress;
            expectedTransferInUsdt = _tokenAmount.convertFromBase18(
                ERC20(_usdtAddress).decimals()
            );
            IERC20(_usdtAddress).safeTransfer(
                _recipient,
                expectedTransferInUsdt
            );
        }
    }

    modifier isCurrentRoundInProgress() {
        if (
            !(block.timestamp < currentRoundEndTime &&
                isRoundInProgress[currentRound])
        ) revert RoundIsNotInProgress();
        _;
    }
}
