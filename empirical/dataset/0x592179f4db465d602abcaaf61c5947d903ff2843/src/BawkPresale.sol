// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import "./interfaces/IAggregator.sol";

// import "hardhat/console.sol";

contract BawkPresale is
    UUPSUpgradeable,
    PausableUpgradeable,
    Ownable2StepUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    enum Currency {
        ETH,
        USDT
    }

    uint public totalTokensSold;
    uint public currentStep;

    uint[21] public stageTokenAmounts;
    uint[21] public stageTokenPrices;
    uint8 constant maxStepIndex = 20;

    IERC20 public USDTInterface;
    IAggregator public aggregatorInterface;

    EnumerableSet.AddressSet internal _presaleUsers;
    mapping(address => uint) _userDeposits;
    mapping(address => bool) public blacklist;

    event TokensBought(
        address indexed user,
        uint indexed tokensBought,
        Currency indexed curr,
        uint amountPaid,
        uint timestamp
    );

    modifier checkSaleState(uint amount) {
        require(amount > 0, "Invalid sale amount");
        require(
            amount + totalTokensSold <= stageTokenAmounts[maxStepIndex],
            "Insufficient supply"
        );
        _;
    }

    modifier notBlacklisted() {
        require(!blacklist[_msgSender()], "You are in blacklist");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Creates the contract
     * @param _aggregatorInterface  - Address of Chainlink ETH/USD price feed
     * @param _USDTInterface        - Address of USDT token
     * @param _stageTokenAmounts    - Array of totalTokenSold limit for each step
     * @param _stageTokenPrices     - Array of prices for each presale step
     */
    function initialize(
        address _aggregatorInterface,
        address _USDTInterface,
        uint[21] memory _stageTokenAmounts,
        uint[21] memory _stageTokenPrices
    ) public virtual initializer {
        __ReentrancyGuard_init();
        __Ownable_init();
        __Pausable_init();
        require(_aggregatorInterface != address(0), "Zero aggregator address");
        require(_USDTInterface != address(0), "Zero USDT address");
        aggregatorInterface = IAggregator(_aggregatorInterface);
        USDTInterface = IERC20(_USDTInterface);
        stageTokenAmounts = _stageTokenAmounts;
        stageTokenPrices = _stageTokenPrices;
    }

    /**
     * @dev To pause the presale
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev To unpause the presale
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev To add users to blacklist
     * @param _users - Array of addresses to add in blacklist
     */
    function addToBlacklist(address[] calldata _users) external onlyOwner {
        uint usersAmount = _users.length;
        uint i = 0;
        while (i < usersAmount) blacklist[_users[i++]] = true;
    }

    /**
     * @dev To remove users from blacklist
     * @param _users - Array of addresses to remove from blacklist
     */
    function removeFromBlacklist(address[] calldata _users) external onlyOwner {
        uint usersAmount = _users.length;
        uint i = 0;
        while (i < usersAmount) blacklist[_users[i++]] = false;
    }

    /**
     * @dev Returns price for current step
     */
    function getCurrentPrice() external view returns (uint) {
        return stageTokenPrices[currentStep];
    }

    function getCurrentStageGoal() external view returns (uint) {
        uint goal;
        for (uint8 i = 0; i <= currentStep; i++) {
            goal +=
                stageTokenPrices[i] *
                (stageTokenAmounts[i] -
                    ((i == 0) ? 0 : stageTokenAmounts[i - 1]));
        }
        return goal;
    }

    /**
     * @dev Returns amount of tokens sold on current step
     */
    function getSoldOnCurrentStage()
        external
        view
        returns (uint soldOnCurrentStage)
    {
        soldOnCurrentStage =
            totalTokensSold -
            ((currentStep == 0) ? 0 : stageTokenAmounts[currentStep - 1]);
    }

    /**
     * @dev Returns presale last stage token amount limit
     */
    function getTotalPresaleAmount() external view returns (uint) {
        return stageTokenAmounts[maxStepIndex];
    }

    /**
     * @dev Returns total price of sold tokens
     * @notice Value may be inaccurate, since not all tokens were sold on the beta presale
     */
    function totalSoldPrice() external view returns (uint) {
        return _calculateInternalCost(totalTokensSold, 0, 0);
    }

    /**
     * @dev Returns total price of sold tokens
     * @param _tokenAddress - Address of token to resque
     * @param _amount       - Amount of tokens to resque
     */
    function resqueERC20(
        address _tokenAddress,
        uint _amount
    ) external onlyOwner {
        IERC20(_tokenAddress).safeTransfer(_msgSender(), _amount);
    }

    /**
     * @dev Returns tokens purchased by the user
     * @param _user - Address of user
     * @notice Takes into account the number of tokens purchased by the user on the previous presale and beta presale
     */
    function userDeposits(address _user) public view returns (uint) {
        return _userDeposits[_user];
    }

    /**
     * @dev To buy into a presale using ETH
     * @param _amount - Amount of tokens to buy
     */
    function buyWithEth(
        uint _amount
    )
        external
        payable
        checkSaleState(_amount)
        notBlacklisted
        whenNotPaused
        nonReentrant
    {
        uint ethAmount = ethBuyHelper(_amount);
        require(msg.value >= ethAmount, "Less payment");
        _sendValue(payable(owner()), ethAmount);
        uint excess = msg.value - ethAmount;
        if (excess > 0) _sendValue(payable(_msgSender()), excess);
        totalTokensSold += _amount;
        _presaleUsers.add(_msgSender());
        _userDeposits[_msgSender()] += _amount * 1e18;
        uint8 stepAfterPurchase = _getStepByTotalSoldAmount();
        if (stepAfterPurchase > currentStep) currentStep = stepAfterPurchase;
        emit TokensBought(_msgSender(), _amount, Currency.ETH, ethAmount, block.timestamp);
    }

    /**
     * @dev To buy into a presale using USDT
     * @param _amount - Amount of tokens to buy
     */
    function buyWithUSDT(
        uint _amount
    )
        external
        checkSaleState(_amount)
        notBlacklisted
        whenNotPaused
        nonReentrant
        returns (bool)
    {
        uint usdtPrice = usdtBuyHelper(_amount);
        require(
            usdtPrice <= USDTInterface.allowance(_msgSender(), address(this)),
            "Not enough allowance"
        );
        USDTInterface.safeTransferFrom(_msgSender(), owner(), usdtPrice);
        totalTokensSold += _amount;
        _presaleUsers.add(_msgSender());
        _userDeposits[_msgSender()] += _amount * 1e18;
        uint8 stepAfterPurchase = _getStepByTotalSoldAmount();
        if (stepAfterPurchase > currentStep) currentStep = stepAfterPurchase;
        emit TokensBought(_msgSender(), _amount, Currency.USDT, usdtPrice, block.timestamp);
        return true;
    }

    /**
     * @dev To get latest ETH/USD price
     * @notice Return result in 1e18 format
     */
    function getLatestPrice() public view returns (uint) {
        (, int256 price, , , ) = aggregatorInterface.latestRoundData();
        return uint(price * 1e10);
    }

    /**
     * @dev Calculate ETH price for given amount
     * @param _amount - Amount of tokens to calculate price
     * @notice Return result in 1e18 format
     */
    function ethBuyHelper(uint _amount) public view returns (uint ethAmount) {
        ethAmount = (calculatePrice(_amount) * 1e18) / getLatestPrice();
    }

    /**
     * @dev Calculate USDT price for given amount
     * @param _amount - Amount of tokens to calculate price
     * @notice Return result in 1e6 format
     */
    function usdtBuyHelper(uint _amount) public view returns (uint usdtPrice) {
        usdtPrice = calculatePrice(_amount) / 1e12;
    }

    /**
     * @dev To calculate the price in USD for given amount of tokens
     * @param _amount - Amount of tokens to calculate price
     * @notice Return result in 1e18 format
     */
    function calculatePrice(uint _amount) public view returns (uint) {
        require(
            _amount + totalTokensSold <= stageTokenAmounts[maxStepIndex],
            "Insufficient token amount."
        );
        return _calculateInternalCost(_amount, currentStep, totalTokensSold);
    }

    /**
     * @dev For sending ETH from contract
     * @param _recipient - Recipient address
     * @param _weiAmount - Amount of ETH to send in wei
     */
    function _sendValue(address payable _recipient, uint _weiAmount) internal {
        require(address(this).balance >= _weiAmount, "Low balance");
        (bool success, ) = _recipient.call{value: _weiAmount}("");
        require(success, "ETH Payment failed");
    }

    /**
     * @dev Recursively calculate cost for specified conditions
     * @param _amount          - Amount of tokens to calculate price
     * @param _currentStep     - Starting step to calculate price
     * @param _totalTokensSold - Starting total token sold amount to calculate price
     */
    function _calculateInternalCost(
        uint _amount,
        uint _currentStep,
        uint _totalTokensSold
    ) internal view returns (uint cost) {
        uint currentPrice = stageTokenPrices[_currentStep];
        uint currentAmount = stageTokenAmounts[_currentStep];
        if (_totalTokensSold + _amount <= currentAmount) {
            cost = _amount * currentPrice;
        } else {
            uint currentStageAmount = currentAmount - _totalTokensSold;
            uint nextStageAmount = _amount - currentStageAmount;
            cost =
                currentStageAmount *
                currentPrice +
                _calculateInternalCost(
                    nextStageAmount,
                    _currentStep + 1,
                    currentAmount
                );
        }

        return cost;
    }

    /**
     * @dev Calculate current step amount from total tokens sold amount
     */
    function _getStepByTotalSoldAmount() internal view returns (uint8) {
        uint8 stepIndex = maxStepIndex;
        while (stepIndex > 0) {
            if (stageTokenAmounts[stepIndex - 1] < totalTokensSold) break;
            stepIndex -= 1;
        }
        return stepIndex;
    }

    // required by the OZ UUPS module
    function _authorizeUpgrade(address) internal override onlyOwner {}

    // =======
    // Getters
    // =======

    /// @notice Get the number of users who participated in the presale
    /// @return Length of _presaleUsers
    function getPresaleUsersCount() external view returns (uint) {
        return _presaleUsers.length();
    }

    /// @notice Get the addresses of users who participated in the presale within a specific range
    /// @param _fromIdx Start index of the desired range
    /// @param _toIdx End index of the desired range
    /// @return partOfPresaleUsers Array of addresses of the presale
    function getPresaleUsers(
        uint _fromIdx,
        uint _toIdx
    ) external view returns (address[] memory partOfPresaleUsers) {
        _toIdx = Math.min(_toIdx, _presaleUsers.length());
        uint range = _toIdx - _fromIdx;
        partOfPresaleUsers = new address[](range);
        for (uint i = 0; i < range; i++) {
            partOfPresaleUsers[i] = _presaleUsers.at(i + _fromIdx);
        }
    }

    uint[50] private __gap;
}
