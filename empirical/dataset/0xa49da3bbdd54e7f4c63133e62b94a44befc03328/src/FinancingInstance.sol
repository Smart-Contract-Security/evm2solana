// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {PhaseScheduleLib} from "./lib/PhaseScheduleLib.sol";
import {FinancingDataStorage} from "./FinancingDataStorage.sol";
import {FinancingTypes} from "./FinancingTypes.sol";
import {BondingCurveMath} from "./lib/BondingCurveMath.sol";

/// @dev paymentToken and shareToken must be standard non-fee-on-transfer ERC20 tokens.
/// @dev View functions, COO config, and ERC1155 are in FinancingInstanceExt, routed via fallback.
contract FinancingInstance is Initializable, FinancingDataStorage {
    using SafeERC20 for IERC20;
    using PhaseScheduleLib for PhaseScheduleLib.Schedule;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    event Checked(address indexed account, uint256 amount, uint256 weightShares);
    event Unchecked(address indexed account, uint256 amount, uint256 burnedWeightShares);
    event UncheckFeePaid(address indexed account, address indexed recipient, uint256 feeAmount);
    event TradeFeePaid(address indexed account, address indexed recipient, uint256 feeAmount, bool isBuy);
    event Bought(address indexed account, uint256 shares, uint256 paymentAmount);
    event Sold(address indexed account, uint256 shares, uint256 proceeds);
    event PurchasedSharesMinted(address indexed account, uint256 shares);
    event UnderlyingSharesClaimed(address indexed account, uint256 shares);
    event ProjectRedeemableSharesClaimed(address indexed account, uint256 shares);
    event ProjectRepaid(address indexed account, uint256 amount);
    event ProjectWithdrawn(address indexed account, uint256 amount);
    event CreatorTransferred(address indexed previousCreator, address indexed newCreator);
    event Phase1Extended(address indexed account, uint64 extraSeconds);
    event Phase2Extended(address indexed account, uint64 extraSeconds);
    event ProjectCleared(
        uint256 indexed orderId,
        uint256 principalSettlementPool,
        uint256 interestPool,
        uint256 profitPool,
        uint256 debtSharesUsed,
        uint256 projectRedeemableShares,
        uint256 finalProjectWithdrawableAmount
    );
    event CheckSettled(
        address indexed account,
        uint256 principalReturn,
        uint256 interestReward,
        uint256 profitReward,
        uint256 debtShares,
        uint256 lossAmount
    );

    // ================================================================
    //  Initialization
    // ================================================================

    function initialize(
        address admin,
        address factory_,
        address extension_,
        uint256 orderId_,
        address creator_,
        FinancingTypes.OrderInitParams calldata params
    ) external initializer {
        _shareClaimUri = "";
        _extensionContract = extension_;
        _FinancingDataStorage_initialize(admin, factory_, orderId_, creator_, params);
    }

    function setExtension(address extension_) external onlyRole(UPGRADER_ROLE) {
        if (extension_ == address(0) || extension_.code.length == 0) revert InvalidReceiver();
        try FinancingInstance(extension_).STORAGE_LAYOUT_VERSION() returns (uint256 v) {
            if (v != STORAGE_LAYOUT_VERSION) revert InvalidReceiver();
        } catch {
            revert InvalidReceiver();
        }
        _extensionContract = extension_;
    }

    // ================================================================
    //  Fallback → delegatecall to extension
    // ================================================================

    fallback() external {
        address ext = _extensionContract;
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), ext, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    // ================================================================
    //  Check Operations
    // ================================================================

    function check(uint256 amount, uint256 minWeightShares) external nonReentrant whenNotPaused {
        _syncLifecycleState();
        _requirePhase1Or2();
        if (amount == 0) revert AmountZero();
        if (_checkState.checkedPrincipal + amount > _maxCheckedPrincipal()) {
            revert CheckCapExceeded();
        }

        PhaseScheduleLib.Stage stage = _currentStage();
        uint256 weightShares = _checkWeightForStage(amount, stage);
        if (weightShares < minWeightShares) revert SlippageExceeded();

        _paymentToken().safeTransferFrom(msg.sender, address(this), amount);

        _incrementCheckParticipant(msg.sender);

        FinancingTypes.CheckPosition storage position = _checkPositions[msg.sender];
        position.principal += amount;
        position.weightShares += weightShares;

        _checkState.checkedPrincipal += amount;
        _checkState.checkedWeightShares += weightShares;

        _syncLifecycleState();
        emit Checked(msg.sender, amount, weightShares);
    }

    function uncheck(uint256 amount) external nonReentrant whenNotPaused {
        _syncLifecycleState();
        _requirePhase1();
        if (amount == 0) revert AmountZero();

        FinancingTypes.CheckPosition storage position = _checkPositions[msg.sender];
        uint256 principal = position.principal;
        if (amount > principal) revert InsufficientCheckPrincipal();

        uint256 burnedWeightShares = Math.mulDiv(position.weightShares, amount, principal);

        position.principal = principal - amount;
        position.weightShares -= burnedWeightShares;

        _checkState.checkedPrincipal -= amount;
        _checkState.checkedWeightShares -= burnedWeightShares;
        _decrementCheckParticipantIfEmpty(msg.sender);

        uint256 feeAmount = Math.mulDiv(amount, _uncheckFeeRateWad, WAD);
        uint256 refundAmount = amount - feeAmount;

        if (feeAmount > 0) {
            _paymentToken().safeTransfer(_protocolFeeRecipient, feeAmount);
            emit UncheckFeePaid(msg.sender, _protocolFeeRecipient, feeAmount);
        }
        _paymentToken().safeTransfer(msg.sender, refundAmount);
        emit Unchecked(msg.sender, amount, burnedWeightShares);
    }

    // ================================================================
    //  Buy / Sell Operations
    // ================================================================

    function buyExactShares(uint256 sharesToBuy, uint256 maxPayment) external nonReentrant whenNotPaused {
        _syncLifecycleState();
        _requirePhase2();
        if (sharesToBuy == 0) revert AmountZero();
        if (sharesToBuy > _remainingSaleShares()) revert InsufficientSaleShares();

        uint256 paymentAmount =
            BondingCurveMath.quoteBuyExactSharesRaw(_curveParams(), _saleState.soldShares, sharesToBuy);
        uint256 feeAmount = _buyFee(paymentAmount);
        if (paymentAmount + feeAmount > maxPayment) revert SlippageExceeded();

        _recordBuy(msg.sender, sharesToBuy, paymentAmount, feeAmount);
    }

    function buyWithExactPayment(uint256 paymentAmount, uint256 minSharesOut) external nonReentrant whenNotPaused {
        _syncLifecycleState();
        _requirePhase2();
        if (paymentAmount == 0) revert AmountZero();
        if (_remainingSaleShares() == 0) revert InsufficientSaleShares();

        uint256 netPaymentBudget = Math.mulDiv(paymentAmount, WAD, WAD + _buyFeeRateWad);
        (uint256 sharesOut, uint256 rawCost) =
            BondingCurveMath.quoteBuySharesForRawPayment(_curveParams(), _saleState.soldShares, netPaymentBudget);
        if (sharesOut == 0) revert SlippageExceeded();
        if (sharesOut < minSharesOut) revert SlippageExceeded();

        _recordBuy(msg.sender, sharesOut, rawCost, _buyFee(rawCost));
    }

    function sellExactShares(uint256 sharesToSell, uint256 minProceeds) external nonReentrant whenNotPaused {
        _syncLifecycleState();
        _requirePhase2();
        if (sharesToSell == 0) revert AmountZero();

        FinancingTypes.BuyerPosition storage buyer = _buyerPositions[msg.sender];
        uint256 sellableShares = buyer.purchasedShares - buyer.mintedShares;
        if (sharesToSell > sellableShares) revert InsufficientBuyerShares();

        uint256 proceeds = BondingCurveMath.quoteSellExactSharesRaw(_curveParams(), _saleState.soldShares, sharesToSell);
        uint256 feeAmount = _sellFee(proceeds);
        uint256 netProceeds = proceeds - feeAmount;
        if (netProceeds < minProceeds) revert SlippageExceeded();
        if (proceeds > _paymentBalance()) revert WithdrawalNotAvailable();

        _recordSell(msg.sender, buyer, sharesToSell, proceeds, feeAmount);
    }

    function sellForExactPayment(uint256 targetPayment, uint256 maxSharesToSell) external nonReentrant whenNotPaused {
        _syncLifecycleState();
        _requirePhase2();
        if (targetPayment == 0 || maxSharesToSell == 0) revert AmountZero();

        FinancingTypes.BuyerPosition storage buyer = _buyerPositions[msg.sender];
        uint256 sellableShares = buyer.purchasedShares - buyer.mintedShares;
        if (maxSharesToSell > sellableShares) revert InsufficientBuyerShares();

        uint256 grossTargetPayment = Math.mulDiv(targetPayment, WAD, WAD - _sellFeeRateWad);
        if (Math.mulDiv(grossTargetPayment, WAD - _sellFeeRateWad, WAD) < targetPayment) {
            grossTargetPayment += 1;
        }

        (uint256 sharesToSell, uint256 proceeds) = BondingCurveMath.quoteSellSharesForTargetRawProceeds(
            _curveParams(), _saleState.soldShares, grossTargetPayment
        );
        if (sharesToSell > maxSharesToSell) revert SlippageExceeded();
        uint256 feeAmount = _sellFee(proceeds);
        uint256 netProceeds = proceeds - feeAmount;
        if (netProceeds < targetPayment) revert SlippageExceeded();
        if (proceeds > _paymentBalance()) revert WithdrawalNotAvailable();

        _recordSell(msg.sender, buyer, sharesToSell, proceeds, feeAmount);
    }

    // ================================================================
    //  Mint / Claim Operations
    // ================================================================

    function mintPurchasedShares(uint256 shares) external nonReentrant whenNotPaused {
        _syncLifecycleState();
        _requireMintWindow();
        if (shares == 0) revert AmountZero();

        FinancingTypes.BuyerPosition storage buyer = _buyerPositions[msg.sender];
        uint256 mintableShares = buyer.purchasedShares - buyer.mintedShares;
        if (shares > mintableShares) revert InsufficientBuyerShares();

        buyer.mintedShares += shares;
        _saleState.mintedSharesTotal += shares;
        _saleState.unmintedSharesTotal -= shares;

        _mintShareClaims(msg.sender, _meta.orderId, shares, "");
        emit PurchasedSharesMinted(msg.sender, shares);
    }

    function claimReleasedUnderlyingShares(uint256 shares) external nonReentrant whenNotPaused {
        _syncLifecycleState();
        _requireProjectClearedAfterPhase2();
        if (shares == 0) revert AmountZero();

        uint256 claimableShares = _claimableUnderlyingShares(msg.sender);
        if (shares > claimableShares) revert WithdrawalNotAvailable();

        _claimedUnderlyingByClaimHolder[msg.sender] += shares;
        _escrowState.buyerClaimedUnderlyingShares += shares;
        _escrowState.redeemedShareAmount += shares;

        _shareToken().safeTransfer(msg.sender, shares);
        emit UnderlyingSharesClaimed(msg.sender, shares);
    }

    function syncEscrowCompletion() external whenNotPaused {
        _syncEscrowCompletion();
        if (_escrowState.escrowCompletedAt == 0) revert NotFullyEscrowed();
    }

    // ================================================================
    //  Project Operations
    // ================================================================

    function setProjectWithdrawTo(address receiver) external onlyRole(PROJECT_ROLE) {
        if (receiver == address(0)) revert InvalidReceiver();
        _config.projectWithdrawTo = receiver;
        emit ProjectWithdrawToUpdated(receiver);
    }

    function transferCreator(address newCreator) external whenNotPaused {
        if (msg.sender != _meta.creator) revert UnauthorizedOperator();
        if (newCreator == address(0)) revert InvalidCreator();

        address previousCreator = _meta.creator;
        if (newCreator == previousCreator) revert InvalidCreator();

        _meta.creator = newCreator;
        _revokeRole(PROJECT_ROLE, previousCreator);
        _grantRole(PROJECT_ROLE, newCreator);

        emit CreatorTransferred(previousCreator, newCreator);
    }

    function setShareToken(address shareToken_) external whenNotPaused onlyRole(PROJECT_ROLE) {
        if (_config.shareToken != address(0)) revert InvalidOrderConfig();
        if (shareToken_ == address(0) || shareToken_.code.length == 0) revert InvalidOrderConfig();
        _config.shareToken = shareToken_;
        emit ShareTokenUpdated(shareToken_);
    }

    function setShareReleaseConfig(uint64 cliff, uint256 initialUnlockWad, uint64 linearDuration)
        external
        whenNotPaused
        onlyRole(PROJECT_ROLE)
    {
        _syncLifecycleState();
        (, uint64 phase1End,,) = _phaseBounds();
        if (block.timestamp + 24 hours >= phase1End) revert InvalidPhase();

        _validateShareReleaseConfig(cliff, initialUnlockWad, linearDuration);

        _config.shareReleaseCliff = cliff;
        _config.shareReleaseInitialUnlockWad = initialUnlockWad;
        _config.shareReleaseLinearDuration = linearDuration;

        emit ShareReleaseConfigUpdated(cliff, initialUnlockWad, linearDuration);
    }

    function extendPhase1(uint64 extraSeconds) external nonReentrant whenNotPaused onlyRole(PROJECT_ROLE) {
        _syncLifecycleState();
        PhaseScheduleLib.Stage stage = _currentStage();
        if (stage != PhaseScheduleLib.Stage.NOT_STARTED && stage != PhaseScheduleLib.Stage.PHASE_1) {
            revert InvalidPhase();
        }
        if (extraSeconds == 0) revert InvalidDuration();
        if (_settlementState.phase1ExtendedSeconds + extraSeconds > MAX_PHASE1_EXTENSION_TOTAL) {
            revert InvalidDuration();
        }

        _payScheduleExtensionFee(_phase1ExtensionFeeAmount, 1);
        _settlementState.phase1ExtendedSeconds += extraSeconds;
        _schedule.extendPhase1(extraSeconds);
        emit Phase1Extended(msg.sender, extraSeconds);
    }

    function extendPhase2(uint64 extraSeconds) external nonReentrant whenNotPaused onlyRole(PROJECT_ROLE) {
        _syncLifecycleState();
        PhaseScheduleLib.Stage stage = _currentStage();
        if (stage != PhaseScheduleLib.Stage.PHASE_2) revert InvalidPhase();
        if (extraSeconds == 0 || extraSeconds > MAX_PHASE2_EXTENSION_EACH) revert InvalidDuration();
        if (_settlementState.phase2ExtensionCount >= MAX_PHASE2_EXTENSION_COUNT) revert InvalidDuration();

        _payScheduleExtensionFee(_phase2ExtensionFeeAmount, 2);
        _settlementState.phase2ExtensionCount += 1;
        _schedule.extendPhase2(extraSeconds);
        emit Phase2Extended(msg.sender, extraSeconds);
    }

    function projectWithdraw(uint256 amount) external nonReentrant whenNotPaused onlyRole(PROJECT_ROLE) {
        _syncLifecycleState();
        PhaseScheduleLib.Stage stage = _currentStage();
        bool finalWithdrawWindow =
            stage == PhaseScheduleLib.Stage.PHASE_4 && _settlementState.projectCleared && _canProjectFinalize();
        if (!finalWithdrawWindow) {
            _syncEscrowCompletion();
        }
        if (amount == 0) revert AmountZero();
        if (!finalWithdrawWindow && _isFullyEscrowed() && !_isEscrowWithdrawUnlocked()) {
            revert EscrowLockupNotEnded();
        }

        uint256 withdrawable = _availableForProjectWithdraw();
        if (amount > withdrawable) revert WithdrawalNotAvailable();

        _saleState.projectWithdrawnAmount += amount;

        if (stage == PhaseScheduleLib.Stage.PHASE_2 && _saleState.projectWithdrawnAmount >= _preFundingTarget()) {
            _settlementState.initialProjectWithdrawCompleted = true;
        }
        if (stage == PhaseScheduleLib.Stage.PHASE_4) {
            _settlementState.projectFinalWithdrawableAmount -= amount;
        }

        _paymentToken().safeTransfer(_config.projectWithdrawTo, amount);
        emit ProjectWithdrawn(msg.sender, amount);
    }

    function projectRepay(uint256 amount) external nonReentrant whenNotPaused onlyRole(PROJECT_ROLE) {
        _syncLifecycleState();
        _requirePhase3Or4();
        if (_settlementState.projectCleared) revert AlreadySettled();
        if (amount == 0) revert AmountZero();

        _paymentToken().safeTransferFrom(msg.sender, address(this), amount);
        _saleState.projectRepaidAmount += amount;

        emit ProjectRepaid(msg.sender, amount);
    }

    function claimProjectRedeemableShares(uint256 shares) external nonReentrant whenNotPaused onlyRole(PROJECT_ROLE) {
        _syncLifecycleState();
        _requirePhase4();
        if (!_settlementState.projectCleared || !_canProjectFinalize()) {
            revert SettlementNotComplete();
        }
        if (shares == 0) revert AmountZero();
        if (shares > _escrowState.projectRedeemableShares) revert WithdrawalNotAvailable();
        if (_shareToken().balanceOf(address(this)) < shares + _reservedUnderlyingShares()) {
            revert WithdrawalNotAvailable();
        }

        _escrowState.projectRedeemableShares -= shares;
        _escrowState.redeemedShareAmount += shares;

        _shareToken().safeTransfer(_config.projectWithdrawTo, shares);
        emit ProjectRedeemableSharesClaimed(msg.sender, shares);
    }

    function claimFailedEscrowedShares(uint256 shares) external nonReentrant whenNotPaused onlyRole(PROJECT_ROLE) {
        _syncLifecycleState();
        if (!_isPhase1FailureEffective()) revert InvalidPhase();
        if (shares == 0) revert AmountZero();

        uint256 remainingEscrow = _config.totalCommittedShares - _escrowState.failedEscrowClaimedShares;
        uint256 claimableShares = Math.min(remainingEscrow, _shareToken().balanceOf(address(this)));
        if (shares > claimableShares) revert WithdrawalNotAvailable();

        _escrowState.failedEscrowClaimedShares += shares;
        _shareToken().safeTransfer(_config.projectWithdrawTo, shares);
        emit ProjectFailedEscrowClaimed(_config.projectWithdrawTo, shares);
    }

    // ================================================================
    //  Settlement
    // ================================================================

    function projectClear() external nonReentrant whenNotPaused {
        _syncLifecycleState();
        _requirePhase3Or4();
        if (!_settlementState.phase1TargetReached) revert Phase1NotSuccessful();
        if (_settlementState.projectCleared) revert AlreadySettled();
        if (!_isProjectClearDelayEnded()) revert ProjectClearDelayNotEnded();
        if (!_isFullyEscrowed()) revert NotFullyEscrowed();

        FinancingTypes.ProjectClearPreview memory preview = _previewProjectClear();

        if (preview.checkProfitFeeAmount > 0) {
            _paymentToken().safeTransfer(_protocolFeeRecipient, preview.checkProfitFeeAmount);
            emit CheckProfitFeePaid(_protocolFeeRecipient, preview.checkProfitFeeAmount);
        }

        _checkState.principalSettlementPool = preview.principalSettlementPool;
        _checkState.interestPool = preview.interestPool;
        _checkState.checkProfitPool = preview.checkProfitPool;
        _checkState.checkLossAmount = preview.checkLossAmount;
        _checkState.settlementReserve = preview.settlementReserve;

        _escrowState.sharesUsedForDebt = preview.debtSharesUsed;
        _escrowState.projectRedeemableShares = preview.projectRedeemableShares;

        _markProjectCleared(preview.finalProjectWithdrawableAmount);
        _openCheckSettlement();

        emit ProjectCleared(
            _meta.orderId,
            preview.principalSettlementPool,
            preview.interestPool,
            preview.checkProfitPool,
            preview.debtSharesUsed,
            preview.projectRedeemableShares,
            preview.finalProjectWithdrawableAmount
        );
    }

    function settleCheck() external nonReentrant whenNotPaused {
        _syncLifecycleState();
        if (_isPhase1FailureEffective()) {
            _requirePhase4();
        } else {
            _requirePhase3Or4();
        }
        if (!_isPhase1FailureEffective() && (!_checkState.checkSettlementOpened || !_settlementState.projectCleared)) {
            revert CheckSettlementNotOpened();
        }

        FinancingTypes.CheckPosition storage position = _checkPositions[msg.sender];
        if (position.settled) revert AlreadySettled();
        if (position.principal == 0 && position.weightShares == 0) revert NothingToSettle();

        FinancingTypes.SettlementResult memory result = _previewSettlement(msg.sender);
        if (
            result.principalReturn == 0 && result.interestReward == 0 && result.profitReward == 0
                && result.debtShareAmount == 0 && result.lossAmount == 0
        ) revert NothingToSettle();

        position.settled = true;
        position.claimedPrincipal = result.principalReturn;
        position.claimedInterest = result.interestReward;
        position.claimedProfit = result.profitReward;
        position.debtShares = result.debtShareAmount;
        position.principal = 0;
        position.weightShares = 0;

        _checkState.settledCheckCount += 1;

        uint256 paymentAmount = result.principalReturn + result.interestReward + result.profitReward;
        if (paymentAmount > 0) {
            _paymentToken().safeTransfer(msg.sender, paymentAmount);
        }
        if (result.debtShareAmount > 0) {
            _escrowState.checkDebtClaimedShares += result.debtShareAmount;
            _escrowState.redeemedShareAmount += result.debtShareAmount;
            _shareToken().safeTransfer(msg.sender, result.debtShareAmount);
        }

        if (_hasCompletedCheckSettlement()) {
            _meta.status = FinancingTypes.LifecycleStatus.CHECK_SETTLEMENT_COMPLETE;
        }

        emit CheckSettled(
            msg.sender,
            result.principalReturn,
            result.interestReward,
            result.profitReward,
            result.debtShareAmount,
            result.lossAmount
        );
    }

    // ================================================================
    //  Internal Helpers
    // ================================================================

    function _recordBuy(address account, uint256 sharesBought, uint256 paymentAmount, uint256 feeAmount) internal {
        _paymentToken().safeTransferFrom(account, address(this), paymentAmount + feeAmount);
        if (feeAmount > 0) {
            _paymentToken().safeTransfer(_protocolFeeRecipient, feeAmount);
            emit TradeFeePaid(account, _protocolFeeRecipient, feeAmount, true);
        }

        FinancingTypes.BuyerPosition storage buyer = _buyerPositions[account];
        buyer.purchasedShares += sharesBought;
        buyer.paidAmount += paymentAmount + feeAmount;

        _saleState.soldShares += sharesBought;
        _saleState.unmintedSharesTotal += sharesBought;
        _saleState.saleReceivedAmount += paymentAmount;

        emit Bought(account, sharesBought, paymentAmount + feeAmount);
    }

    function _recordSell(
        address account,
        FinancingTypes.BuyerPosition storage buyer,
        uint256 sharesSold,
        uint256 grossProceeds,
        uint256 feeAmount
    ) internal {
        buyer.purchasedShares -= sharesSold;
        if (buyer.paidAmount <= grossProceeds) {
            buyer.paidAmount = 0;
        } else {
            buyer.paidAmount -= grossProceeds;
        }

        _saleState.soldShares -= sharesSold;
        _saleState.unmintedSharesTotal -= sharesSold;
        _saleState.salePaidOutAmount += grossProceeds;

        uint256 netProceeds = grossProceeds - feeAmount;
        if (feeAmount > 0) {
            _paymentToken().safeTransfer(_protocolFeeRecipient, feeAmount);
            emit TradeFeePaid(account, _protocolFeeRecipient, feeAmount, false);
        }
        _paymentToken().safeTransfer(account, netProceeds);
        emit Sold(account, sharesSold, netProceeds);
    }

    function _buyFee(uint256 paymentAmount) internal view returns (uint256) {
        return Math.mulDiv(paymentAmount, _buyFeeRateWad, WAD);
    }

    function _sellFee(uint256 grossProceeds) internal view returns (uint256) {
        return Math.mulDiv(grossProceeds, _sellFeeRateWad, WAD);
    }

    function _checkProfitProtocolFee(uint256 grossProfitPool) internal view returns (uint256) {
        uint256 thresholdAmount = Math.mulDiv(_config.targetAmount, _checkProfitFeeThresholdWad, WAD);
        if (grossProfitPool < thresholdAmount) return 0;
        return Math.mulDiv(grossProfitPool, _checkProfitFeeRateWad, WAD);
    }

    function _payScheduleExtensionFee(uint256 feeAmount, uint8 phase) internal {
        if (feeAmount == 0) return;
        uint256 rawFeeAmount = _rawPaymentAmount(feeAmount);
        _paymentToken().safeTransferFrom(msg.sender, _protocolFeeRecipient, rawFeeAmount);
        emit ScheduleExtensionFeePaid(msg.sender, _protocolFeeRecipient, rawFeeAmount, phase);
    }

    function _requireProjectClearedAfterPhase2() internal view {
        PhaseScheduleLib.Stage stage = _currentStage();
        if (stage != PhaseScheduleLib.Stage.PHASE_3 && stage != PhaseScheduleLib.Stage.PHASE_4) return;
        if (!_settlementState.projectCleared) revert SettlementNotComplete();
    }

    function _isPhase1FailureEffective() internal view returns (bool) {
        if (_settlementState.phase1Failed) return true;
        if (_isPhase1SuccessEffective()) return false;
        (, uint64 phase1End,,) = _phaseBounds();
        return block.timestamp >= phase1End && _checkState.checkedPrincipal < _preFundingTarget();
    }

    function _isPhase1SuccessEffective() internal view returns (bool) {
        if (_settlementState.phase1TargetReached) return true;
        (, uint64 phase1End,,) = _phaseBounds();
        return block.timestamp >= phase1End && _checkState.checkedPrincipal >= _preFundingTarget();
    }

    function _previewProjectClear() internal view returns (FinancingTypes.ProjectClearPreview memory preview) {
        preview.paymentBalance = _paymentBalance();
        preview.checkedPrincipal = _checkState.checkedPrincipal;
        preview.principalSettlementPool = Math.min(preview.paymentBalance, preview.checkedPrincipal);
        uint256 remainingCash = preview.paymentBalance - preview.principalSettlementPool;

        preview.interestPool = Math.min(remainingCash, _interestAccruedAmount());
        remainingCash -= preview.interestPool;

        preview.grossProfitPool = Math.min(remainingCash, _saleProfitAmount());
        remainingCash -= preview.grossProfitPool;

        preview.checkProfitFeeAmount = _checkProfitProtocolFee(preview.grossProfitPool);
        preview.checkProfitPool = preview.grossProfitPool - preview.checkProfitFeeAmount;

        preview.principalShortfall = preview.checkedPrincipal - preview.principalSettlementPool;
        preview.debtSharesUsed = _debtSharesForRawAmount(preview.principalShortfall);
        uint256 unsoldEscrowShares = _config.totalCommittedShares - _saleState.soldShares;
        if (preview.debtSharesUsed > unsoldEscrowShares) {
            preview.debtSharesUsed = unsoldEscrowShares;
        }

        preview.debtCoverageAmount = _rawAmountAtMinPrice(preview.debtSharesUsed);
        if (preview.debtCoverageAmount > preview.principalShortfall) {
            preview.debtCoverageAmount = preview.principalShortfall;
        }

        preview.checkLossAmount = preview.principalShortfall - preview.debtCoverageAmount;
        preview.settlementReserve = preview.principalSettlementPool + preview.interestPool + preview.checkProfitPool;
        preview.projectRedeemableShares = unsoldEscrowShares - preview.debtSharesUsed;

        uint256 remainingTargetCapacity;
        if (_config.targetAmount > _saleState.projectWithdrawnAmount) {
            remainingTargetCapacity = _config.targetAmount - _saleState.projectWithdrawnAmount;
        }
        preview.finalProjectWithdrawableAmount = Math.min(remainingCash, remainingTargetCapacity);
    }

    function _previewSettlement(address account) internal view returns (FinancingTypes.SettlementResult memory result) {
        FinancingTypes.CheckPosition storage position = _checkPositions[account];
        if (position.settled) return result;
        if (position.principal == 0 || _checkState.checkedPrincipal == 0) return result;

        if (_isPhase1FailureEffective()) {
            result.principalReturn = position.principal;
            return result;
        }

        uint256 totalPrincipal = _checkState.checkedPrincipal;
        uint256 totalWeight = _checkState.checkedWeightShares;

        result.principalReturn = Math.mulDiv(_checkState.principalSettlementPool, position.principal, totalPrincipal);
        result.lossAmount = Math.mulDiv(_checkState.checkLossAmount, position.principal, totalPrincipal);
        result.debtShareAmount = Math.mulDiv(_escrowState.sharesUsedForDebt, position.principal, totalPrincipal);

        if (totalWeight > 0) {
            result.interestReward = Math.mulDiv(_checkState.interestPool, position.weightShares, totalWeight);
            result.profitReward = Math.mulDiv(_checkState.checkProfitPool, position.weightShares, totalWeight);
        }
    }

    function _maxProjectWithdrawableCumulative() internal view returns (uint256) {
        PhaseScheduleLib.Stage stage = _currentStage();

        if (stage == PhaseScheduleLib.Stage.PHASE_4 && _settlementState.projectCleared && _canProjectFinalize()) {
            return Math.min(
                _config.targetAmount,
                _saleState.projectWithdrawnAmount + _settlementState.projectFinalWithdrawableAmount
            );
        }

        if (!_isFullyEscrowed() || !_isEscrowWithdrawUnlocked() || !_isPhase1SuccessEffective()) {
            return _saleState.projectWithdrawnAmount;
        }

        if (stage == PhaseScheduleLib.Stage.PHASE_2) {
            uint256 checkPrincipalCap = _checkState.checkedPrincipal / 2;
            uint256 realTimeCap =
                Math.max(_preFundingTarget(), Math.min(Math.mulDiv(_config.targetAmount, 60, 100), checkPrincipalCap));
            return Math.max(_saleState.projectWithdrawnAmount, realTimeCap);
        }

        return _saleState.projectWithdrawnAmount;
    }

    function _availableForProjectWithdraw() internal view returns (uint256) {
        PhaseScheduleLib.Stage stage = _currentStage();

        if (stage == PhaseScheduleLib.Stage.PHASE_4 && _settlementState.projectCleared && _canProjectFinalize()) {
            return Math.min(_settlementState.projectFinalWithdrawableAmount, _paymentBalance());
        }

        if (!_isFullyEscrowed() || !_isPhase1SuccessEffective()) return 0;
        if (!_isEscrowWithdrawUnlocked()) return 0;

        if (stage == PhaseScheduleLib.Stage.PHASE_2) {
            uint256 cumulativeCap = _maxProjectWithdrawableCumulative();
            if (cumulativeCap <= _saleState.projectWithdrawnAmount) return 0;

            uint256 capRemaining = cumulativeCap - _saleState.projectWithdrawnAmount;
            uint256 reserve = _reserveRequiredForSell() + _reserveRequiredForCheckSettlement();
            uint256 balance = _paymentBalance();
            if (balance <= reserve) return 0;
            return Math.min(capRemaining, balance - reserve);
        }

        return 0;
    }

    function _reserveRequiredForSell() internal view returns (uint256) {
        if (_currentStage() != PhaseScheduleLib.Stage.PHASE_2) return 0;
        uint256 unmintedShares = _unmintedSoldShares();
        if (unmintedShares == 0) return 0;
        return BondingCurveMath.quoteSellExactSharesRaw(_curveParams(), _saleState.soldShares, unmintedShares);
    }

    function _reserveRequiredForCheckSettlement() internal view returns (uint256) {
        if (_settlementState.projectCleared) return _checkState.settlementReserve;
        return _saleProfitAmount() + _interestAccruedAmount();
    }

    function _rawAmountAtMinPrice(uint256 sharesAmount) internal view returns (uint256) {
        if (sharesAmount == 0) return 0;
        return Math.mulDiv(Math.mulDiv(_config.priceMinWad, sharesAmount, WAD), _config.paymentUnit, WAD);
    }

    function _debtSharesForRawAmount(uint256 rawAmount) internal view returns (uint256) {
        if (rawAmount == 0) return 0;
        uint256 pricePerWholeShareRaw = Math.mulDiv(_config.priceMinWad, _config.paymentUnit, WAD);
        if (pricePerWholeShareRaw == 0) return 0;
        return Math.ceilDiv(rawAmount * WAD, pricePerWholeShareRaw);
    }

    event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value);

    function _mintShareClaims(address to, uint256 id, uint256 amount, bytes memory data) internal {
        if (to == address(0)) revert InvalidReceiver();
        _shareClaimBalances[id][to] += amount;
        emit TransferSingle(msg.sender, address(0), to, id, amount);

        if (to.code.length > 0) {
            bytes4 response = IERC1155Receiver(to).onERC1155Received(msg.sender, address(0), id, amount, data);
            if (response != IERC1155Receiver.onERC1155Received.selector) revert TransfersDisabled();
        }
    }
}
