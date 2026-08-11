// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PhaseScheduleLib} from "./lib/PhaseScheduleLib.sol";

library FinancingTypes {
    uint256 internal constant WAD = 1e18;

    enum LifecycleStatus {
        UNINITIALIZED,
        ACTIVE,
        PHASE1_FAILED,
        PHASE1_SUCCEEDED,
        PROJECT_CLEARED,
        CHECK_SETTLEMENT_OPEN,
        CHECK_SETTLEMENT_COMPLETE
    }

    struct FinancingOrderMeta {
        uint256 orderId;
        address creator;
        LifecycleStatus status;
    }

    struct FinancingConfig {
        address paymentToken;
        address projectWithdrawTo;
        address shareToken;
        uint256 targetAmount;
        uint256 preFundingRateWad;
        uint256 totalCommittedShares;
        uint256 priceMinWad;
        uint256 priceMaxWad;
        uint256 lambdaWad;
        uint256 paymentUnit;
        uint256 annualInterestRateWad;
        uint64 shareReleaseCliff;
        uint256 shareReleaseInitialUnlockWad;
        uint64 shareReleaseLinearDuration;
    }

    struct SaleState {
        uint256 soldShares;
        uint256 mintedSharesTotal;
        uint256 unmintedSharesTotal;
        uint256 saleReceivedAmount;
        uint256 salePaidOutAmount;
        uint256 projectWithdrawnAmount;
        uint256 projectRepaidAmount;
    }

    struct CheckState {
        uint256 checkedPrincipal;
        uint256 checkedWeightShares;
        uint256 principalSettlementPool;
        uint256 interestPool;
        uint256 checkProfitPool;
        uint256 checkLossAmount;
        uint256 settlementReserve;
        uint256 checkParticipantCount;
        uint256 settledCheckCount;
        bool checkSettlementOpened;
    }

    struct EscrowState {
        uint64 escrowCompletedAt;
        uint256 escrowedShares;
        uint256 redeemedShareAmount;
        uint256 buyerClaimedUnderlyingShares;
        uint256 checkDebtClaimedShares;
        uint256 sharesUsedForDebt;
        uint256 projectRedeemableShares;
        uint256 failedEscrowClaimedShares;
    }

    struct SettlementState {
        uint64 phase1SucceededAt;
        uint64 clearedAt;
        uint64 phase1ExtendedSeconds;
        uint8 phase2ExtensionCount;
        uint256 projectFinalWithdrawableAmount;
        bool phase1TargetReached;
        bool phase1Failed;
        bool initialProjectWithdrawCompleted;
        bool projectCleared;
    }

    struct FinancingOrderView {
        FinancingOrderMeta meta;
        FinancingConfig config;
        SaleState sale;
        CheckState check;
        EscrowState escrow;
        SettlementState settlement;
    }

    struct FinancingOrderCompactView {
        FinancingOrderMeta meta;
        FinancingConfig config;
        SaleState sale;
        CheckState check;
    }

    struct FinancingOrderSettlementView {
        EscrowState escrow;
        SettlementState settlement;
        CheckState check;
    }

    struct CheckPosition {
        uint256 principal;
        uint256 weightShares;
        uint256 claimedPrincipal;
        uint256 claimedProfit;
        uint256 claimedInterest;
        uint256 debtShares;
        bool settled;
    }

    struct BuyerPosition {
        uint256 purchasedShares;
        uint256 mintedShares;
        uint256 paidAmount;
        uint256 claimedUnderlyingShares;
    }

    struct SettlementResult {
        uint256 principalReturn;
        uint256 interestReward;
        uint256 profitReward;
        uint256 debtShareAmount;
        uint256 lossAmount;
    }

    struct ProtocolConfigView {
        address protocolFeeRecipient;
        uint256 uncheckFeeRateWad;
        uint256 buyFeeRateWad;
        uint256 sellFeeRateWad;
        uint256 checkProfitFeeThresholdWad;
        uint256 checkProfitFeeRateWad;
        uint256 phase1ExtensionFeeAmount;
        uint256 phase2ExtensionFeeAmount;
        uint64 projectClearDelay;
        uint64 projectFinalizationDelay;
    }

    struct ProjectClearPreview {
        uint256 paymentBalance;
        uint256 checkedPrincipal;
        uint256 principalSettlementPool;
        uint256 interestPool;
        uint256 grossProfitPool;
        uint256 checkProfitFeeAmount;
        uint256 checkProfitPool;
        uint256 principalShortfall;
        uint256 debtSharesUsed;
        uint256 debtCoverageAmount;
        uint256 checkLossAmount;
        uint256 settlementReserve;
        uint256 projectRedeemableShares;
        uint256 finalProjectWithdrawableAmount;
    }

    struct ProjectWithdrawPreview {
        PhaseScheduleLib.Stage currentStage;
        uint256 paymentBalance;
        uint256 cumulativeCap;
        uint256 alreadyWithdrawn;
        uint256 capRemaining;
        uint256 sellReserve;
        uint256 checkSettlementReserve;
        uint256 totalReserve;
        uint256 balanceAfterReserve;
        uint256 availableWithdrawable;
        bool fullyEscrowed;
        bool escrowWithdrawUnlocked;
        bool phase1SuccessEffective;
        bool finalWithdrawWindow;
        bool projectCanFinalize;
    }

    struct OrderInitParams {
        address paymentToken;
        address projectWithdrawTo;
        address shareToken;
        uint256 preFundingRateWad;
        uint256 totalCommittedShares;
        uint256 priceMinWad;
        uint256 priceMaxWad;
        uint256 lambdaWad;
        uint256 paymentUnit;
        uint64 scheduleStartAt;
        uint64 phase2Duration;
        uint256 escrowedShares;
        uint256 annualInterestRateWad;
        uint64 shareReleaseCliff;
        uint256 shareReleaseInitialUnlockWad;
        uint64 shareReleaseLinearDuration;
    }

    struct OrderView {
        FinancingOrderView order;
        PhaseScheduleLib.Stage currentStage;
        uint64 startAt;
        uint64 phase1End;
        uint64 phase2End;
        uint64 phase3End;
    }
}
