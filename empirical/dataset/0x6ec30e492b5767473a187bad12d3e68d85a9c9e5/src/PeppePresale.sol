// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";

interface IPriceFeed {
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

contract PeppePresale is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    IERC20 public presaleToken;
    IERC20 public usdtToken;
    IPriceFeed public ethPriceFeed;
    address public wertPermiter;

    uint256 public INITIAL_TOKEN_PRICE;
    uint256 public WEEKLY_INCREASE;
    uint256 public MAX_PRICE_INCREASE;
    uint256 public tokensSold;
    uint256 public startTime;
    uint256 public endTime;

    mapping(address => uint256) public userPurchases;

    enum PaymentMethod {
        ETH,
        USDT
    }

    event TokensPurchased(
        address indexed buyer,
        uint256 tokenAmount,
        uint256 paymentAmount,
        PaymentMethod paymentMethod,
        uint256 usdValue
    );

    event FundsWithdrawn(uint256 ethAmount, uint256 usdtAmount);
    event SaleDatesUpdated(uint256 newStartTime, uint256 newEndTime);

    function initialize(
        address _owner,
        address _ethPriceFeed,
        address _usdtToken,
        address _presaleToken
    ) public initializer {
        __Ownable_init(_owner);
        __ReentrancyGuard_init();

        ethPriceFeed = IPriceFeed(_ethPriceFeed);
        usdtToken = IERC20(_usdtToken);
        presaleToken = IERC20(_presaleToken);

        INITIAL_TOKEN_PRICE = 3101000000000000;
        WEEKLY_INCREASE = 36025000000000;
        startTime = 1748304000;
        endTime = 1760400000;
        tokensSold = 0;
    }


    modifier onlyDuringPresale() {
        require(block.timestamp >= startTime, "Presale not started");
        require(block.timestamp <= endTime, "Presale ended");
        _;
    }

    modifier afterPresale() {
        require(block.timestamp > endTime, "Presale still active");
        _;
    }

    modifier wertOnly() {
        require(msg.sender == wertPermiter, "Only Wert");
        _;
    }

    function buyWithETH() external payable onlyDuringPresale nonReentrant {
        require(msg.value > 0, "Must send ETH");

        uint256 ethPrice = getETHPrice();
        uint256 currentTokenPrice = getTokenPrice();
        uint256 usdValue = (msg.value * ethPrice) / 1e18;
        uint256 tokenAmount = (usdValue * 1e18) / currentTokenPrice;

        require(tokenAmount > 0, "Insufficient payment for any tokens");

        _processPurchase(
            msg.sender,
            tokenAmount,
            msg.value,
            usdValue,
            PaymentMethod.ETH
        );
    }

    function buyWithUSDT(
        uint256 usdtAmount
    ) external onlyDuringPresale nonReentrant {
        require(usdtAmount > 0, "USDT amount must be greater than 0");

        uint256 currentTokenPrice = getTokenPrice();
        // USDT is pegged to $1, so 1 USDT = $1 USD
        // USDT has 6 decimals, so we need to convert to 18 decimals for calculation
        uint256 usdValue = usdtAmount * 1e12; // Convert USDT (6 decimals) to 18 decimals
        uint256 tokenAmount = (usdValue * 1e18) / currentTokenPrice;

        require(tokenAmount > 0, "Insufficient payment for any tokens");

        usdtToken.safeTransferFrom(msg.sender, address(this), usdtAmount);
        _processPurchase(
            msg.sender,
            tokenAmount,
            usdtAmount,
            usdValue,
            PaymentMethod.USDT
        );
    }

    function buyWithWert(
        address _user
    ) external payable nonReentrant wertOnly {
        require(_user != address(0), "Invalid user address");


        uint256 ethPrice = getETHPrice();
        uint256 currentTokenPrice = getTokenPrice();
        uint256 usdValue = (msg.value * ethPrice) / 1e18;
        uint256 tokenAmount = (usdValue * 1e18) / currentTokenPrice;

        require(tokenAmount > 0, "Insufficient payment for any tokens");

        _processPurchase(
            _user,
            tokenAmount,
            msg.value,
            usdValue,
            PaymentMethod.ETH
        );
    }

    function _processPurchase(
        address buyer,
        uint256 tokenAmount,
        uint256 paymentAmount,
        uint256 usdValue,
        PaymentMethod method
    ) internal {
        tokensSold += tokenAmount;
        userPurchases[buyer] += tokenAmount;

        emit TokensPurchased(
            buyer,
            tokenAmount,
            paymentAmount,
            method,
            usdValue
        );
    }

    function calculateTokenAmount(
        uint256 paymentAmount,
        PaymentMethod method
    ) external view returns (uint256) {
        uint256 usdValue;
        uint256 currentTokenPrice = getTokenPrice();

        if (method == PaymentMethod.ETH) {
            uint256 ethPrice = getETHPrice();
            usdValue = (paymentAmount * ethPrice) / 1e18;
        } else {
            // USDT to USD (1:1 ratio, convert 6 decimals to 18)
            usdValue = paymentAmount * 1e12;
        }

        return (usdValue * 1e18) / currentTokenPrice;
    }

    function claimTokens() external nonReentrant afterPresale {

        uint256 userTokenAmount = userPurchases[msg.sender];
        require(userTokenAmount > 0, "No tokens to claim");

        userPurchases[msg.sender] = 0;
        presaleToken.safeTransfer(msg.sender, userTokenAmount);
    }

    function getTokenPrice() public view returns (uint256) {
        require(block.timestamp <= endTime, "Presale has ended");
        if (block.timestamp < startTime) {
            return INITIAL_TOKEN_PRICE; // Initial price $0.0031
        }

        uint256 passedTime = block.timestamp - startTime;
        uint256 weeksElapsed = passedTime / (86400 * 7); // 7 days per week

        uint256 priceIncrease = weeksElapsed * WEEKLY_INCREASE;

        return INITIAL_TOKEN_PRICE + priceIncrease;
    }

    function getETHPrice() public view returns (uint256) {
        (, int256 price, , , ) = ethPriceFeed.latestRoundData();
        require(price > 0, "Invalid ETH price");
        return uint256(price) * 1e10; // Convert to 18 decimals (Chainlink returns 8 decimals)
    }

    function updateSaleDates(
        uint256 newStartTime,
        uint256 newEndTime
    ) external onlyOwner {
        require(newStartTime > block.timestamp, "Start time must be in future");
        require(newEndTime > newStartTime, "End time must be after start");
        startTime = newStartTime;
        endTime = newEndTime;
    }

    function withdrawFunds() external onlyOwner afterPresale {
        uint256 ethBalance = address(this).balance;
        uint256 usdtBalance = usdtToken.balanceOf(address(this));

        if (ethBalance > 0) {
            payable(owner()).transfer(ethBalance);
        }

        if (usdtBalance > 0) {
            usdtToken.safeTransfer(owner(), usdtBalance);
        }

        emit FundsWithdrawn(ethBalance, usdtBalance);
    }

    function emergencyWithdrawTokens(
        address token,
        uint256 amount
    ) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);
    }

    // View functions
    function getPresaleInfo()
        external
        view
        returns (
            uint256 _currentTokenPrice,
            uint256 _tokensSold,
            uint256 _startTime,
            uint256 _endTime,
            bool _isActive
        )
    {
        return (
            getTokenPrice(),
            tokensSold,
            startTime,
            endTime,
            block.timestamp >= startTime && block.timestamp <= endTime
        );
    }

    function getUserPurchase(address user) external view returns (uint256) {
        return userPurchases[user];
    }

    function getCurrentETHPrice() external view returns (uint256) {
        return getETHPrice();
    }

    function setWertPermiter(address _wertPermiter) external onlyOwner {
        require(
            _wertPermiter != address(0),
            "Wert permiter cannot be zero address"
        );
        wertPermiter = _wertPermiter;
    }

    function setEndTime(uint256 _endTime) external onlyOwner {
        require(_endTime > block.timestamp, "End time must be in future");
        endTime = _endTime;
    }

    function setStartTime(uint256 _startTime) external onlyOwner {
        startTime = _startTime;
    }
}
