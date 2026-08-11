// SPDX-License-Identifier: AGPL-3.0-only

import {NestShareOFT} from "contracts/NestShareOFT.sol";

contract NestAccountant {
    struct AccountantState {
        address payoutAddress;
        uint128 feesOwedInBase;
        uint128 totalSharesLastUpdate;
        uint96 exchangeRate;
        uint32 allowedExchangeRateChangeUpper;
        uint32 allowedExchangeRateChangeLower;
        uint64 lastUpdateTimestamp;
        bool isPaused;
        uint32 minimumUpdateDelayInSeconds;
        uint32 managementFee;
    }

    struct RateProviderData {
        bool isPeggedToBase;
        address rateProvider;
    }

    struct NestAccountantStorage {
        AccountantState accountantState;
        mapping(address => RateProviderData) rateProviderData;
        uint256 totalPendingShares;
    }

    address public immutable base;
    uint8 public immutable baseDecimals;
    address internal immutable SHARE;

    uint256 internal constant DENOMINATOR = 1e6;
    uint256 internal constant MANAGEMENT_FEE_CAP = 0.2e6;
    uint256 internal constant ONE_YEAR = 365 days;
    uint256 internal constant UPDATE_DELAY_CAP = 14 days;

    bytes32 private constant NestAccountantStorageLocation =
        0xb378036f9633fc394c3579301b38ac88997c2589544525e367cd650f76eaa300;

    event FeesClaimed(address indexed feeAsset, uint256 amount);
    event TotalPendingSharesUpdated(uint256 oldPendingShares, uint256 newPendingShares);
    event Paused();
    event Unpaused();
    event DelayInSecondsUpdated(uint32 oldDelay, uint32 newDelay);
    event UpperBoundUpdated(uint32 oldBound, uint32 newBound);
    event LowerBoundUpdated(uint32 oldBound, uint32 newBound);
    event ManagementFeeUpdated(uint32 oldFee, uint32 newFee);
    event PayoutAddressUpdated(address oldPayout, address newPayout);
    event RateProviderUpdated(address asset, bool isPegged, address rateProvider);
    event ExchangeRateUpdated(uint96 oldRate, uint96 newRate, uint64 currentTime);
    event ExchangeRateUpdatePaused(uint96 oldRate, uint96 newRate, uint64 currentTime);

    address private _owner;

    modifier requiresAuth() {
        require(msg.sender == _owner, "Not authorized");
        _;
    }

    constructor(address _base, address _share) {
        require(_base != address(0) && _share != address(0), "ZeroAddress");
        base = _base;
        baseDecimals = ERC20(_base).decimals();
        SHARE = _share;
    }

    function _getNestAccountantStorage() private pure returns (NestAccountantStorage storage $) {
        assembly {
            $.slot := NestAccountantStorageLocation
        }
    }

    function initialize(
        uint256 _totalSharesLastUpdate,
        address _payoutAddress,
        uint96 _startingExchangeRate,
        uint32 _allowedExchangeRateChangeUpper,
        uint32 _allowedExchangeRateChangeLower,
        uint32 _minimumUpdateDelayInSeconds,
        uint32 _managementFee,
        address _ownerAddr
    ) external {
        require(_owner == address(0), "Already initialized");
        require(_startingExchangeRate != 0, "InvalidRate");
        require(_ownerAddr != address(0), "ZeroAddress");
        _owner = _ownerAddr;
        AccountantState storage accountantState = _getNestAccountantStorage().accountantState;
        accountantState.lastUpdateTimestamp = uint64(block.timestamp);
        accountantState.totalSharesLastUpdate = _toUint128(_totalSharesLastUpdate);
        accountantState.exchangeRate = _startingExchangeRate;
        _setPayoutAddress(accountantState, _payoutAddress);
        _setAllowedExchangeRateChangeUpper(accountantState, _allowedExchangeRateChangeUpper);
        _setAllowedExchangeRateChangeLower(accountantState, _allowedExchangeRateChangeLower);
        _setMinimumUpdateDelayInSeconds(accountantState, _minimumUpdateDelayInSeconds);
        _setManagementFee(accountantState, _managementFee);
    }

    function version() public pure returns (string memory) {
        return "1.1.0";
    }

    function claimFees(address _feeAsset) external {
        require(msg.sender == SHARE, "OnlyCallableByNestShare");

        AccountantState storage accountantState = _getNestAccountantStorage().accountantState;

        require(!accountantState.isPaused, "Paused");
        require(accountantState.feesOwedInBase != 0, "ZeroFeesOwed");

        uint256 _feesOwedInFeeAsset;
        uint256 _remainder;
        if (_feeAsset == base) {
            _feesOwedInFeeAsset = accountantState.feesOwedInBase;
        } else {
            RateProviderData memory _data = _getNestAccountantStorage().rateProviderData[_feeAsset];
            uint8 _feeAssetDecimals = ERC20(_feeAsset).decimals();
            (uint256 _feesOwedInBaseUsingFeeAssetDecimals, uint256 remainder_) =
                _changeDecimals(accountantState.feesOwedInBase, baseDecimals, _feeAssetDecimals);
            _remainder = remainder_;
            if (_data.isPeggedToBase) {
                _feesOwedInFeeAsset = _feesOwedInBaseUsingFeeAssetDecimals;
            } else {
                uint256 _rate = IRateProvider(_data.rateProvider).getRate();
                _feesOwedInFeeAsset = _feesOwedInBaseUsingFeeAssetDecimals * (10 ** _feeAssetDecimals) / _rate;
            }
        }

        accountantState.feesOwedInBase = _toUint128(_remainder);
        SafeERC20.safeTransferFrom(
            _feeAsset, SHARE, accountantState.payoutAddress, _feesOwedInFeeAsset
        );

        emit FeesClaimed(_feeAsset, _feesOwedInFeeAsset);
    }

    function pause() external requiresAuth {
        _getNestAccountantStorage().accountantState.isPaused = true;
        emit Paused();
    }

    function unpause() external requiresAuth {
        _getNestAccountantStorage().accountantState.isPaused = false;
        emit Unpaused();
    }

    function updateDelay(uint32 _minimumUpdateDelayInSeconds) external requiresAuth {
        AccountantState storage accountantState = _getNestAccountantStorage().accountantState;
        uint32 _oldDelay = accountantState.minimumUpdateDelayInSeconds;
        _setMinimumUpdateDelayInSeconds(accountantState, _minimumUpdateDelayInSeconds);
        emit DelayInSecondsUpdated(_oldDelay, _minimumUpdateDelayInSeconds);
    }

    function updateUpper(uint32 _allowedExchangeRateChangeUpper) external requiresAuth {
        AccountantState storage accountantState = _getNestAccountantStorage().accountantState;
        uint32 _oldBound = accountantState.allowedExchangeRateChangeUpper;
        _setAllowedExchangeRateChangeUpper(accountantState, _allowedExchangeRateChangeUpper);
        emit UpperBoundUpdated(_oldBound, _allowedExchangeRateChangeUpper);
    }

    function updateLower(uint32 _allowedExchangeRateChangeLower) external requiresAuth {
        AccountantState storage accountantState = _getNestAccountantStorage().accountantState;
        uint32 _oldBound = accountantState.allowedExchangeRateChangeLower;
        _setAllowedExchangeRateChangeLower(accountantState, _allowedExchangeRateChangeLower);
        emit LowerBoundUpdated(_oldBound, _allowedExchangeRateChangeLower);
    }

    function updateManagementFee(uint32 _managementFee) external requiresAuth {
        AccountantState storage accountantState = _getNestAccountantStorage().accountantState;
        uint32 _oldFee = accountantState.managementFee;

        _accrueManagementFees(accountantState, uint64(block.timestamp), accountantState.exchangeRate);

        _setManagementFee(accountantState, _managementFee);
        emit ManagementFeeUpdated(_oldFee, _managementFee);
    }

    function updatePayoutAddress(address _payoutAddress) external requiresAuth {
        AccountantState storage accountantState = _getNestAccountantStorage().accountantState;
        address _oldPayout = accountantState.payoutAddress;
        _setPayoutAddress(accountantState, _payoutAddress);
        emit PayoutAddressUpdated(_oldPayout, _payoutAddress);
    }

    function setRateProviderData(address asset, bool isPeggedToBase, address rateProvider) external requiresAuth {
        require(isPeggedToBase || rateProvider != address(0), "ZeroAddress");
        _getNestAccountantStorage().rateProviderData[asset] =
            RateProviderData({isPeggedToBase: isPeggedToBase, rateProvider: rateProvider});
        emit RateProviderUpdated(asset, isPeggedToBase, rateProvider);
    }

    function updateExchangeRate(uint96 _newExchangeRate) external requiresAuth {
        AccountantState storage accountantState = _getNestAccountantStorage().accountantState;
        uint64 _currentTime = uint64(block.timestamp);

        uint256 _currentExchangeRate = accountantState.exchangeRate;

        require(_currentTime >= accountantState.lastUpdateTimestamp + accountantState.minimumUpdateDelayInSeconds, "MinimumUpdateDelayNotPassed");
        require(
            _newExchangeRate <= _currentExchangeRate * accountantState.allowedExchangeRateChangeUpper / DENOMINATOR
                && _newExchangeRate >= _currentExchangeRate * accountantState.allowedExchangeRateChangeLower / DENOMINATOR,
            "RateOutOfBounds"
        );

        _accrueManagementFees(accountantState, _currentTime, _newExchangeRate);

        accountantState.exchangeRate = _newExchangeRate;

        emit ExchangeRateUpdated(uint96(_currentExchangeRate), _newExchangeRate, _currentTime);
    }

    function getRate() public view returns (uint256 rate) {
        NestAccountantStorage storage $ = _getNestAccountantStorage();
        rate = $.accountantState.exchangeRate;
    }

    function getRateSafe() external view returns (uint256 rate) {
        NestAccountantStorage storage $ = _getNestAccountantStorage();
        require(!$.accountantState.isPaused, "Paused");
        rate = $.accountantState.exchangeRate;
    }

    function getRateInQuote(address _quote) public view returns (uint256 _rateInQuote) {
        NestAccountantStorage storage $ = _getNestAccountantStorage();
        AccountantState storage accountantState = $.accountantState;
        if (_quote == base) {
            _rateInQuote = accountantState.exchangeRate;
        } else {
            RateProviderData memory _data = $.rateProviderData[_quote];
            uint8 _quoteDecimals = ERC20(_quote).decimals();
            (uint256 _exchangeRateInQuoteDecimals,) =
                _changeDecimals(accountantState.exchangeRate, baseDecimals, _quoteDecimals);
            if (_data.isPeggedToBase) {
                _rateInQuote = _exchangeRateInQuoteDecimals;
            } else {
                uint256 _quoteRate = IRateProvider(_data.rateProvider).getRate();
                uint256 _oneQuote = 10 ** _quoteDecimals;
                _rateInQuote = _oneQuote * _exchangeRateInQuoteDecimals / _quoteRate;
            }
        }
    }

    function getRateInQuoteSafe(address _quote) public view returns (uint256 _rateInQuote) {
        NestAccountantStorage storage $ = _getNestAccountantStorage();
        require(!$.accountantState.isPaused, "Paused");
        _rateInQuote = getRateInQuote(_quote);
    }

    function getAccountantState() public view returns (AccountantState memory) {
        NestAccountantStorage storage $ = _getNestAccountantStorage();
        return $.accountantState;
    }

    function share() external view returns (address) {
        return SHARE;
    }

    function totalPendingShares() external view returns (uint256) {
        return _getNestAccountantStorage().totalPendingShares;
    }

    function increaseTotalPendingShares(uint256 _amount) external requiresAuth {
        NestAccountantStorage storage $ = _getNestAccountantStorage();
        uint256 _oldPendingShares = $.totalPendingShares;
        $.totalPendingShares = _oldPendingShares + _amount;
        emit TotalPendingSharesUpdated(_oldPendingShares, $.totalPendingShares);
    }

    function decreaseTotalPendingShares(uint256 _amount) external requiresAuth {
        NestAccountantStorage storage $ = _getNestAccountantStorage();
        uint256 _oldPendingShares = $.totalPendingShares;
        require(_amount <= _oldPendingShares, "InsufficientBalance");
        $.totalPendingShares = _oldPendingShares - _amount;
        emit TotalPendingSharesUpdated(_oldPendingShares, $.totalPendingShares);
    }

    function _setMinimumUpdateDelayInSeconds(
        AccountantState storage accountantState,
        uint32 _minimumUpdateDelayInSeconds
    ) internal {
        require(_minimumUpdateDelayInSeconds <= UPDATE_DELAY_CAP, "UpdateDelayTooLarge");
        accountantState.minimumUpdateDelayInSeconds = _minimumUpdateDelayInSeconds;
    }

    function _setAllowedExchangeRateChangeUpper(
        AccountantState storage accountantState,
        uint32 _allowedExchangeRateChangeUpper
    ) internal {
        require(_allowedExchangeRateChangeUpper >= DENOMINATOR, "UpperBoundTooSmall");
        accountantState.allowedExchangeRateChangeUpper = _allowedExchangeRateChangeUpper;
    }

    function _setAllowedExchangeRateChangeLower(
        AccountantState storage accountantState,
        uint32 _allowedExchangeRateChangeLower
    ) internal {
        require(_allowedExchangeRateChangeLower <= DENOMINATOR, "LowerBoundTooLarge");
        accountantState.allowedExchangeRateChangeLower = _allowedExchangeRateChangeLower;
    }

    function _setManagementFee(AccountantState storage accountantState, uint32 _managementFee) internal {
        require(_managementFee <= MANAGEMENT_FEE_CAP, "ManagementFeeTooLarge");
        accountantState.managementFee = _managementFee;
    }

    function _setPayoutAddress(AccountantState storage accountantState, address _payoutAddress) internal {
        require(_payoutAddress != address(0), "ZeroAddress");
        accountantState.payoutAddress = _payoutAddress;
    }

    function _updateAccountingCheckpoints(
        AccountantState storage accountantState,
        uint64 _currentTime,
        uint256 _currentTotalShares
    ) internal {
        accountantState.lastUpdateTimestamp = _currentTime;
        accountantState.totalSharesLastUpdate = _toUint128(_currentTotalShares);
    }

    function _accrueManagementFees(
        AccountantState storage accountantState,
        uint64 _currentTime,
        uint256 _newExchangeRate
    ) internal {
        uint256 _currentTotalShares = IERC20(SHARE).totalSupply();
        uint256 _timeDelta = _currentTime - accountantState.lastUpdateTimestamp;
        uint256 _shareSupplyToUse = min(uint256(accountantState.totalSharesLastUpdate), _currentTotalShares);
        uint256 _rateToAccrueOn = min(uint256(accountantState.exchangeRate), _newExchangeRate);

        uint256 _assets = _shareSupplyToUse * _rateToAccrueOn / (10 ** NestShareOFT(SHARE).decimals());
        uint256 _managementFeesAnnual = _assets * accountantState.managementFee / DENOMINATOR;

        uint256 _feesOwedInBase = uint256(accountantState.feesOwedInBase);
        _feesOwedInBase += _managementFeesAnnual * _timeDelta / ONE_YEAR;

        accountantState.feesOwedInBase = _toUint128(_feesOwedInBase);
        accountantState.lastUpdateTimestamp = _currentTime;
        accountantState.totalSharesLastUpdate = _toUint128(_currentTotalShares);
    }

    function _toUint128(uint256 _value) internal pure returns (uint128 _value128) {
        _value128 = _value > type(uint128).max ? type(uint128).max : uint128(_value);
    }

    function _changeDecimals(uint256 _amount, uint8 _fromDecimals, uint8 _toDecimals)
        internal
        pure
        returns (uint256 _amountAdjusted, uint256 _remainder)
    {
        if (_fromDecimals == _toDecimals) {
            _amountAdjusted = _amount;
        } else if (_fromDecimals < _toDecimals) {
            _amountAdjusted = _amount * 10 ** (_toDecimals - _fromDecimals);
        } else {
            _amountAdjusted = _amount / 10 ** (_fromDecimals - _toDecimals);
            _remainder = _amount % 10 ** (_fromDecimals - _toDecimals);
        }
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

interface ERC20 {
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint256);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IRateProvider {
    function getRate() external view returns (uint256);
}

library SafeERC20 {
    function safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        require(IERC20(token).transferFrom(from, to, amount), "Transfer failed");
    }
}