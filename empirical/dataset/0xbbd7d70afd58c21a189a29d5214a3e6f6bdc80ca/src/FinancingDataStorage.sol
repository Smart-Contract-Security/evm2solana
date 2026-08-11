// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {BaseControl} from "./base/BaseControl.sol";
import {Errors} from "./errors/Errors.sol";
import {BondingCurveMath} from "./lib/BondingCurveMath.sol";
import {PhaseScheduleLib} from "./lib/PhaseScheduleLib.sol";
import {FinancingTypes} from "./FinancingTypes.sol";

abstract contract FinancingDataStorage is BaseControl {
    using SafeERC20 for IERC20;
    using PhaseScheduleLib for PhaseScheduleLib.Schedule;

    /// @dev Shared layout version — Instance and Extension must return the same value.
    ///      Bump this whenever storage variables are added/removed/reordered.
    uint256 public constant STORAGE_LAYOUT_VERSION = 1;

    uint256 internal constant WAD = 1e18;
    uint256 internal constant PHASE1_CHECK_WEIGHT_WAD = 1.2e18;
    uint256 internal constant PHASE2_CHECK_MAX_WEIGHT_WAD = 1e18;
    uint256 internal constant DEFAULT_UNCHECK_FEE_RATE_WAD = 15e15;
    uint256 internal constant DEFAULT_BUY_FEE_RATE_WAD = 1e16;
    uint256 internal constant DEFAULT_SELL_FEE_RATE_WAD = 1e16;
    uint256 internal constant DEFAULT_CHECK_PROFIT_FEE_THRESHOLD_WAD = 1e17;
    uint256 internal constant DEFAULT_CHECK_PROFIT_FEE_RATE_WAD = 15e16;
    uint256 internal constant DEFAULT_LAMBDA_WAD = 2e16;
    uint256 internal constant BPS_WAD = 1e18;
    uint256 internal constant YEAR = 365 days;
    uint64 internal constant PROJECT_WITHDRAW_ESCROW_LOCK = 7 days;
    uint64 internal constant DEFAULT_PROJECT_CLEAR_DELAY = 72 hours;
    uint64 internal constant MAX_PROJECT_CLEAR_DELAY = 14 days;
    uint64 internal constant DEFAULT_PROJECT_FINALIZATION_DELAY = 30 days;
    uint64 internal constant MAX_PROJECT_FINALIZATION_DELAY = 365 days;
    uint64 internal constant MAX_PHASE1_EXTENSION_TOTAL = 30 days;
    uint64 internal constant MAX_PHASE2_EXTENSION_EACH = 30 days;
    uint8 internal constant MAX_PHASE2_EXTENSION_COUNT = 6;

    error InvalidFactory();
    error InvalidCreator();
    error InvalidPaymentToken();
    error InvalidOrderConfig();
    error InvalidPhase();
    error AmountZero();
    error InsufficientCheckPrincipal();
    error InsufficientBuyerShares();
    error SlippageExceeded();
    error NotFullyEscrowed();
    error Phase1NotSuccessful();
    error Phase1AlreadyFailed();
    error CheckSettlementNotOpened();
    error AlreadySettled();
    error NothingToSettle();
    error WithdrawalNotAvailable();
    error SettlementNotComplete();
    error InvalidShareReleaseConfig();
    error InvalidRate();
    error InvalidReceiver();
    error TransfersDisabled();
    error EscrowLockupNotEnded();
    error CheckCapExceeded();
    error InsufficientSaleShares();
    error InvalidDuration();
    error ProjectClearDelayNotEnded();
    error UnauthorizedOperator();
    error SelfApproval();
    error InvalidPaymentTokenDecimals();

    address internal _factory;
    PhaseScheduleLib.Schedule internal _schedule;
    FinancingTypes.FinancingOrderMeta internal _meta;
    FinancingTypes.FinancingConfig internal _config;
    FinancingTypes.SaleState internal _saleState;
    FinancingTypes.CheckState internal _checkState;
    FinancingTypes.EscrowState internal _escrowState;
    FinancingTypes.SettlementState internal _settlementState;
    mapping(address account => FinancingTypes.CheckPosition) internal _checkPositions;
    mapping(address account => FinancingTypes.BuyerPosition) internal _buyerPositions;
    address internal _protocolFeeRecipient;
    uint256 internal _uncheckFeeRateWad;
    uint256 internal _buyFeeRateWad;
    uint256 internal _sellFeeRateWad;
    uint256 internal _checkProfitFeeThresholdWad;
    uint256 internal _checkProfitFeeRateWad;
    uint256 internal _phase1ExtensionFeeAmount;
    uint256 internal _phase2ExtensionFeeAmount;
    uint64 internal _projectClearDelay;
    uint64 internal _projectFinalizationDelay;

    mapping(uint256 id => mapping(address account => uint256)) internal _shareClaimBalances;
    mapping(address account => mapping(address operator => bool)) internal _shareClaimApprovals;
    mapping(address account => uint256) internal _claimedUnderlyingByClaimHolder;
    string internal _shareClaimUri;
    address internal _extensionContract;

    event FinancingInitialized(uint256 indexed orderId, address indexed factory, address indexed creator);
    event ProjectSettlementOpened(uint256 indexed orderId);
    event Phase1FailureMarked(uint256 indexed orderId, uint64 failureEffectiveAt);
    event Phase1Succeeded(uint256 indexed orderId, uint64 successAt, uint256 checkedPrincipal);
    event EscrowCompleted(uint256 indexed orderId, uint64 completedAt, uint256 escrowedShares);
    event ProtocolFeeRecipientUpdated(address indexed recipient);
    event UncheckFeeConfigUpdated(address indexed recipient, uint256 feeRateWad);
    event TradeFeeConfigUpdated(uint256 buyFeeRateWad, uint256 sellFeeRateWad);
    event CheckProfitFeeConfigUpdated(uint256 thresholdRateWad, uint256 feeRateWad);
    event CheckProfitFeePaid(address indexed recipient, uint256 feeAmount);
    event ProjectClearDelayUpdated(uint64 delaySeconds);
    event ProjectFinalizationDelayUpdated(uint64 delaySeconds);
    event ProjectWithdrawToUpdated(address indexed receiver);
    event ShareTokenUpdated(address indexed shareToken);
    event ProjectFailedEscrowClaimed(address indexed receiver, uint256 shares);
    event ShareReleaseConfigUpdated(uint64 cliff, uint256 initialUnlockWad, uint64 linearDuration);
    event ScheduleExtensionFeeConfigUpdated(uint256 phase1FeeAmount, uint256 phase2FeeAmount);
    event ScheduleExtensionFeePaid(address indexed account, address indexed recipient, uint256 amount, uint8 phase);

    function _FinancingDataStorage_initialize(
        address admin,
        address factory_,
        uint256 orderId_,
        address creator_,
        FinancingTypes.OrderInitParams memory params
    ) internal onlyInitializing {
        _BaseControl_initialize(admin);
        _validateInitParams(factory_, orderId_, creator_, params);

        _factory = factory_;
        _protocolFeeRecipient = admin;
        _uncheckFeeRateWad = DEFAULT_UNCHECK_FEE_RATE_WAD;
        _buyFeeRateWad = DEFAULT_BUY_FEE_RATE_WAD;
        _sellFeeRateWad = DEFAULT_SELL_FEE_RATE_WAD;
        _checkProfitFeeThresholdWad = DEFAULT_CHECK_PROFIT_FEE_THRESHOLD_WAD;
        _checkProfitFeeRateWad = DEFAULT_CHECK_PROFIT_FEE_RATE_WAD;
        _projectClearDelay = DEFAULT_PROJECT_CLEAR_DELAY;
        _projectFinalizationDelay = DEFAULT_PROJECT_FINALIZATION_DELAY;

        _meta.orderId = orderId_;
        _meta.creator = creator_;
        _meta.status = FinancingTypes.LifecycleStatus.ACTIVE;

        _config.paymentToken = params.paymentToken;
        _config.projectWithdrawTo = params.projectWithdrawTo;
        _config.shareToken = params.shareToken;
        _config.targetAmount = _targetAmountFrom(params.totalCommittedShares, params.priceMinWad, params.paymentUnit);
        _config.preFundingRateWad = params.preFundingRateWad;
        _config.totalCommittedShares = params.totalCommittedShares;
        _config.priceMinWad = params.priceMinWad;
        _config.priceMaxWad = params.priceMaxWad;
        _config.lambdaWad = params.lambdaWad == 0 ? DEFAULT_LAMBDA_WAD : params.lambdaWad;
        _config.paymentUnit = params.paymentUnit;
        _config.annualInterestRateWad = params.annualInterestRateWad;
        _config.shareReleaseCliff = params.shareReleaseCliff;
        _config.shareReleaseInitialUnlockWad = params.shareReleaseInitialUnlockWad;
        _config.shareReleaseLinearDuration = params.shareReleaseLinearDuration;

        _escrowState.escrowedShares = params.escrowedShares;

        _schedule.initialize(params.scheduleStartAt, params.phase2Duration);
        _grantRole(PROJECT_ROLE, creator_);

        BondingCurveMath.validate(_curveParams());

        emit FinancingInitialized(orderId_, factory_, creator_);
    }

    function _validateInitParams(
        address factory_,
        uint256 orderId_,
        address creator_,
        FinancingTypes.OrderInitParams memory params
    )
        internal
        view
    {
        if (factory_ == address(0)) revert InvalidFactory();
        if (orderId_ == 0) revert InvalidOrderConfig();
        if (creator_ == address(0)) revert InvalidCreator();
        if (params.paymentToken == address(0)) revert InvalidPaymentToken();
        if (params.projectWithdrawTo == address(0)) revert Errors.ZeroAddress();
        if (params.preFundingRateWad == 0 || params.preFundingRateWad > WAD) revert InvalidRate();
        if (params.totalCommittedShares == 0 || params.phase2Duration == 0) revert InvalidOrderConfig();
        if (params.priceMinWad == 0 || params.priceMaxWad <= params.priceMinWad) revert InvalidOrderConfig();
        if (params.paymentUnit == 0 || params.paymentUnit != _expectedPaymentUnit(params.paymentToken)) {
            revert InvalidOrderConfig();
        }
        if (_targetAmountFrom(params.totalCommittedShares, params.priceMinWad, params.paymentUnit) == 0) {
            revert InvalidOrderConfig();
        }
        _validateShareReleaseConfig(
            params.shareReleaseCliff, params.shareReleaseInitialUnlockWad, params.shareReleaseLinearDuration
        );
    }

    function _validateShareReleaseConfig(uint64, uint256 initialUnlockWad, uint64 linearDuration) internal pure {
        if (initialUnlockWad > WAD) revert InvalidShareReleaseConfig();
        if (initialUnlockWad < WAD && linearDuration == 0) revert InvalidShareReleaseConfig();
    }

    function _targetAmountFrom(uint256 totalCommittedShares, uint256 priceMinWad, uint256 paymentUnit)
        internal
        pure
        returns (uint256)
    {
        return Math.mulDiv(Math.mulDiv(priceMinWad, totalCommittedShares, WAD), paymentUnit, WAD);
    }

    function _paymentToken() internal view returns (IERC20) {
        return IERC20(_config.paymentToken);
    }

    function _expectedPaymentUnit(address paymentToken) internal view returns (uint256) {
        uint8 decimals = IERC20Metadata(paymentToken).decimals();
        if (decimals > 18) revert InvalidPaymentTokenDecimals();

        return 10 ** decimals;
    }

    function _rawPaymentAmount(uint256 amountWad) internal view returns (uint256) {
        uint256 result = Math.mulDiv(amountWad, _config.paymentUnit, WAD);
        if (mulmod(amountWad, _config.paymentUnit, WAD) > 0) {
            unchecked {
                result += 1;
            }
        }
        return result;
    }

    function _shareToken() internal view returns (IERC20) {
        if (_config.shareToken == address(0)) revert InvalidOrderConfig();
        return IERC20(_config.shareToken);
    }

    function _curveParams() internal view returns (BondingCurveMath.CurveParams memory p) {
        FinancingTypes.FinancingConfig storage config = _config;
        p = BondingCurveMath.CurveParams({
            totalShares: config.totalCommittedShares,
            priceMinWad: config.priceMinWad,
            priceMaxWad: config.priceMaxWad,
            lambdaWad: config.lambdaWad,
            paymentUnit: config.paymentUnit
        });
    }

    function _preFundingTarget() internal view returns (uint256) {
        return Math.mulDiv(_config.targetAmount, _config.preFundingRateWad, WAD);
    }

    function _maxCheckedPrincipal() internal view returns (uint256) {
        return Math.mulDiv(_config.targetAmount, _config.priceMaxWad, _config.priceMinWad);
    }

    function _remainingSaleShares() internal view returns (uint256) {
        return _config.totalCommittedShares - _saleState.soldShares;
    }

    function _paymentBalance() internal view returns (uint256) {
        return _paymentToken().balanceOf(address(this));
    }

    function _currentEscrowedUnderlying() internal view returns (uint256) {
        if (_config.shareToken == address(0)) return _escrowState.redeemedShareAmount;
        return _shareToken().balanceOf(address(this)) + _escrowState.redeemedShareAmount;
    }

    function _isFullyEscrowed() internal view returns (bool) {
        return _currentEscrowedUnderlying() >= _config.totalCommittedShares;
    }

    function _syncEscrowCompletion() internal {
        if (_escrowState.escrowCompletedAt != 0 || !_isFullyEscrowed()) return;

        _escrowState.escrowCompletedAt = uint64(block.timestamp);
        emit EscrowCompleted(_meta.orderId, uint64(block.timestamp), _currentEscrowedUnderlying());
    }

    function _isEscrowWithdrawUnlocked() internal view returns (bool) {
        uint64 completedAt = _escrowState.escrowCompletedAt;
        if (completedAt == 0) return false;
        return block.timestamp >= completedAt + PROJECT_WITHDRAW_ESCROW_LOCK;
    }

    function _isProjectClearDelayEnded() internal view returns (bool) {
        (,, uint64 phase2End,) = _phaseBounds();
        return block.timestamp >= uint256(phase2End) + _projectClearDelay;
    }

    function _isProjectFinalizationUnlocked() internal view returns (bool) {
        (,,, uint64 phase3End) = _phaseBounds();
        return block.timestamp >= uint256(phase3End) + _projectFinalizationDelay;
    }

    function _phaseBounds()
        internal
        view
        returns (uint64 startAt, uint64 phase1End, uint64 phase2End, uint64 phase3End)
    {
        return _schedule.bounds();
    }

    function _currentStage() internal view returns (PhaseScheduleLib.Stage) {
        (uint64 startAt, uint64 phase1End, uint64 phase2End, uint64 phase3End) = _phaseBounds();
        uint64 nowTs = uint64(block.timestamp);

        if (nowTs < startAt) return PhaseScheduleLib.Stage.NOT_STARTED;
        if (_settlementState.phase1Failed) return PhaseScheduleLib.Stage.PHASE_4;

        if (nowTs < phase1End) return PhaseScheduleLib.Stage.PHASE_1;

        if (_settlementState.phase1TargetReached || _checkState.checkedPrincipal >= _preFundingTarget()) {
            if (nowTs < phase2End) return PhaseScheduleLib.Stage.PHASE_2;
            if (nowTs < phase3End) return PhaseScheduleLib.Stage.PHASE_3;
            return PhaseScheduleLib.Stage.PHASE_4;
        }

        return PhaseScheduleLib.Stage.PHASE_4;
    }

    function _syncLifecycleState() internal {
        if (_settlementState.phase1TargetReached || _settlementState.phase1Failed) return;

        (, uint64 phase1End,,) = _phaseBounds();
        if (block.timestamp < phase1End) return;

        if (_checkState.checkedPrincipal >= _preFundingTarget()) {
            _settlementState.phase1TargetReached = true;
            _settlementState.phase1SucceededAt = phase1End;
            _meta.status = FinancingTypes.LifecycleStatus.PHASE1_SUCCEEDED;
            emit Phase1Succeeded(_meta.orderId, phase1End, _checkState.checkedPrincipal);
            return;
        }

        _markPhase1Failure(phase1End);
    }

    function _requirePhase1Or2() internal view {
        PhaseScheduleLib.Stage stage = _currentStage();
        if (stage != PhaseScheduleLib.Stage.PHASE_1 && stage != PhaseScheduleLib.Stage.PHASE_2) {
            revert InvalidPhase();
        }
    }

    function _requirePhase1() internal view {
        if (_currentStage() != PhaseScheduleLib.Stage.PHASE_1) revert InvalidPhase();
    }

    function _requirePhase2() internal view {
        if (_currentStage() != PhaseScheduleLib.Stage.PHASE_2) revert InvalidPhase();
    }

    function _requirePhase3() internal view {
        if (_currentStage() != PhaseScheduleLib.Stage.PHASE_3) revert InvalidPhase();
    }

    function _requirePhase3Or4() internal view {
        PhaseScheduleLib.Stage stage = _currentStage();
        if (stage != PhaseScheduleLib.Stage.PHASE_3 && stage != PhaseScheduleLib.Stage.PHASE_4) {
            revert InvalidPhase();
        }
    }

    function _requirePhase4() internal view {
        if (_currentStage() != PhaseScheduleLib.Stage.PHASE_4) revert InvalidPhase();
    }

    function _requireMintWindow() internal view {
        PhaseScheduleLib.Stage stage = _currentStage();
        if (
            stage != PhaseScheduleLib.Stage.PHASE_2 && stage != PhaseScheduleLib.Stage.PHASE_3
                && stage != PhaseScheduleLib.Stage.PHASE_4
        ) revert InvalidPhase();
    }

    function _phase2CheckWeightWad() internal view returns (uint256) {
        if (_saleState.soldShares >= _config.totalCommittedShares) return 0;
        uint256 progressWad = Math.mulDiv(_saleState.soldShares, WAD, _config.totalCommittedShares);
        if (progressWad >= PHASE2_CHECK_MAX_WEIGHT_WAD) return 0;
        return PHASE2_CHECK_MAX_WEIGHT_WAD - progressWad;
    }

    function _checkWeightForStage(uint256 amount, PhaseScheduleLib.Stage stage) internal view returns (uint256) {
        if (stage == PhaseScheduleLib.Stage.PHASE_1) {
            return Math.mulDiv(amount, PHASE1_CHECK_WEIGHT_WAD, WAD);
        }
        if (stage == PhaseScheduleLib.Stage.PHASE_2) {
            return Math.mulDiv(amount, _phase2CheckWeightWad(), WAD);
        }
        return 0;
    }

    function _incrementCheckParticipant(address account) internal {
        FinancingTypes.CheckPosition storage position = _checkPositions[account];
        if (position.principal == 0 && !position.settled) {
            _checkState.checkParticipantCount += 1;
        }
    }

    function _decrementCheckParticipantIfEmpty(address account) internal {
        FinancingTypes.CheckPosition storage position = _checkPositions[account];
        if (position.principal == 0 && !position.settled && _checkState.checkParticipantCount > 0) {
            _checkState.checkParticipantCount -= 1;
        }
    }

    function _markProjectCleared(uint256 finalProjectWithdrawableAmount) internal {
        _settlementState.projectCleared = true;
        _settlementState.clearedAt = uint64(block.timestamp);
        _settlementState.projectFinalWithdrawableAmount = finalProjectWithdrawableAmount;
        _meta.status = FinancingTypes.LifecycleStatus.PROJECT_CLEARED;
    }

    function _openCheckSettlement() internal {
        _checkState.checkSettlementOpened = true;
        _meta.status = FinancingTypes.LifecycleStatus.CHECK_SETTLEMENT_OPEN;
        emit ProjectSettlementOpened(_meta.orderId);
    }

    function _markPhase1Failure(uint64 failureEffectiveAt) internal {
        _schedule.markPhase1Failed(failureEffectiveAt);
        _settlementState.phase1Failed = true;
        _meta.status = FinancingTypes.LifecycleStatus.PHASE1_FAILED;
        emit Phase1FailureMarked(_meta.orderId, failureEffectiveAt);
    }

    function _mintablePurchasedShares(address account) internal view returns (uint256) {
        FinancingTypes.BuyerPosition storage position = _buyerPositions[account];
        return position.purchasedShares - position.mintedShares;
    }

    function _unmintedSoldShares() internal view returns (uint256) {
        return _saleState.unmintedSharesTotal;
    }

    function _netSaleAmount() internal view returns (uint256) {
        return _saleState.saleReceivedAmount - _saleState.salePaidOutAmount;
    }

    function _minPriceFinancingAmountForSoldShares(uint256 soldShares) internal view returns (uint256) {
        return Math.mulDiv(Math.mulDiv(_config.priceMinWad, soldShares, WAD), _config.paymentUnit, WAD);
    }

    function _saleProfitAmount() internal view returns (uint256) {
        uint256 financingComponent = _minPriceFinancingAmountForSoldShares(_saleState.soldShares);
        if (_saleState.saleReceivedAmount <= financingComponent) return 0;
        return _saleState.saleReceivedAmount - financingComponent;
    }

    function _interestAccruedAmount() internal view returns (uint256) {
        if (_checkState.checkedPrincipal == 0) return 0;
        (, uint64 phase1End, uint64 phase2End,) = _phaseBounds();
        bool phase1Succeeded = _settlementState.phase1TargetReached
            || (block.timestamp >= phase1End && _checkState.checkedPrincipal >= _preFundingTarget());
        uint64 fromTs = phase1Succeeded ? phase1End : phase2End;
        uint64 toTs = _settlementState.projectCleared ? _settlementState.clearedAt : uint64(block.timestamp);
        if (toTs <= fromTs) return 0;

        uint256 numerator = _checkState.checkedPrincipal * _config.annualInterestRateWad * (toTs - fromTs);
        return numerator / YEAR / WAD;
    }

    function _releasedRatioWad() internal view returns (uint256) {
        (,,, uint64 phase3End) = _phaseBounds();
        uint64 start = phase3End;
        if (block.timestamp < start + _config.shareReleaseCliff) return 0;

        uint256 unlocked = _config.shareReleaseInitialUnlockWad;
        if (unlocked >= WAD) return WAD;

        uint64 linearStart = start + _config.shareReleaseCliff;
        uint64 elapsed = uint64(block.timestamp) - linearStart;
        if (elapsed >= _config.shareReleaseLinearDuration) return WAD;

        uint256 remaining = WAD - unlocked;
        uint256 linearPart = Math.mulDiv(remaining, elapsed, _config.shareReleaseLinearDuration);
        return unlocked + linearPart;
    }

    function _vestedUnderlyingShares(address account) internal view returns (uint256) {
        return Math.mulDiv(_shareClaimBalance(account), _releasedRatioWad(), WAD);
    }

    function _claimableUnderlyingShares(address account) internal view returns (uint256) {
        uint256 vested = _vestedUnderlyingShares(account);
        uint256 claimed = _claimedUnderlyingShares(account);
        if (vested <= claimed) return 0;
        return vested - claimed;
    }

    function _reservedUnderlyingShares() internal view returns (uint256) {
        uint256 buyerReserve = _saleState.soldShares - _escrowState.buyerClaimedUnderlyingShares;
        uint256 debtReserve = _escrowState.sharesUsedForDebt - _escrowState.checkDebtClaimedShares;
        return buyerReserve + debtReserve;
    }

    function _shareClaimBalance(address account) internal view returns (uint256) {
        return _shareClaimBalances[_meta.orderId][account];
    }

    function _claimedUnderlyingShares(address account) internal view returns (uint256) {
        return _claimedUnderlyingByClaimHolder[account];
    }

    function _hasCompletedCheckSettlement() internal view returns (bool) {
        return _checkState.checkParticipantCount == _checkState.settledCheckCount;
    }

    function _canProjectFinalize() internal view returns (bool) {
        return _hasCompletedCheckSettlement() || _isProjectFinalizationUnlocked();
    }

    function _orderView() internal view returns (FinancingTypes.FinancingOrderView memory viewData) {
        viewData = FinancingTypes.FinancingOrderView({
            meta: _meta,
            config: _config,
            sale: _saleState,
            check: _checkState,
            escrow: _escrowState,
            settlement: _settlementState
        });
    }

    function _compactOrderView() internal view returns (FinancingTypes.FinancingOrderCompactView memory viewData) {
        viewData = FinancingTypes.FinancingOrderCompactView({
            meta: _meta, config: _config, sale: _saleState, check: _checkState
        });
    }

    function _settlementView() internal view returns (FinancingTypes.FinancingOrderSettlementView memory viewData) {
        viewData = FinancingTypes.FinancingOrderSettlementView({
            escrow: _escrowState, settlement: _settlementState, check: _checkState
        });
    }

    function _scheduleStorage() internal view returns (PhaseScheduleLib.Schedule storage) {
        return _schedule;
    }

    function _metaStorage() internal view returns (FinancingTypes.FinancingOrderMeta storage) {
        return _meta;
    }

    function _configStorage() internal view returns (FinancingTypes.FinancingConfig storage) {
        return _config;
    }

    function _saleStateStorage() internal view returns (FinancingTypes.SaleState storage) {
        return _saleState;
    }

    function _checkStateStorage() internal view returns (FinancingTypes.CheckState storage) {
        return _checkState;
    }

    function _escrowStateStorage() internal view returns (FinancingTypes.EscrowState storage) {
        return _escrowState;
    }

    function _settlementStateStorage() internal view returns (FinancingTypes.SettlementState storage) {
        return _settlementState;
    }

    function _checkPosition(address account) internal view returns (FinancingTypes.CheckPosition storage) {
        return _checkPositions[account];
    }

    function _buyerPosition(address account) internal view returns (FinancingTypes.BuyerPosition storage) {
        return _buyerPositions[account];
    }

    // uint256[50] private __gap; 这是一个抽象合约，不能用这个来填充
}
