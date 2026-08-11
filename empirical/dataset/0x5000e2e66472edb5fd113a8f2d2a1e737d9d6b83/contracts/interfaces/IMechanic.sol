// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Hook-facing WETH accounting and payout interface for the mechanic vault.
interface IMechanic {
    enum BuybackNotificationResult {
        NoReserve,
        Armed,
        ExecutionSignaled
    }

    /// @dev Append-only telemetry. `None` is the default for both unprocessed contexts and claimable records.
    /// Disambiguate with `holderApexContextProcessed` and `holderApexIdPlusOneByContext`.
    enum HolderApexSkipReason {
        None,
        EpochZero,
        ZeroHolderWeth,
        ZeroEligibleWeight
    }

    struct HolderApex {
        uint256 contextId;
        uint48 snapshotBlock;
        uint64 snapshotTimestamp;
        uint64 confirmationEpochId;
        uint256 holderWeth;
        uint256 eligibleWeight;
        uint256 totalSnapshotWeight;
        uint256 finalDisqualifiedWeight;
    }

    function weth() external view returns (address);
    function hook() external view returns (address);
    function treasury() external view returns (address);
    function token() external view returns (address);
    function MAX_CLAIM_APEXES_PER_CALL() external view returns (uint256);
    function freeSinkWeth() external view returns (uint256);
    function holderReservedWeth() external view returns (uint256);
    function buybackReservedWeth() external view returns (uint256);
    function treasuryAccruedWeth() external view returns (uint256);
    function buybackDue() external view returns (bool);
    function buybackArmCount() external view returns (uint256);
    function buybackExecutionSignalCount() external view returns (uint256);
    function buybackExecutionSuccessCount() external view returns (uint256);
    function totalBuybackWethSpent() external view returns (uint256);
    function totalBuybackTokenBurned() external view returns (uint256);
    function holderApexCount() external view returns (uint256);
    function nextClaimApex(address holder) external view returns (uint256);
    function claimCursorInitialized(address holder) external view returns (bool);
    function holderApexClaimedWeth(uint256 apexId) external view returns (uint256);
    function holderApexContextProcessed(uint256 contextId) external view returns (bool);
    function holderApexIdPlusOneByContext(uint256 contextId) external view returns (uint256);
    /// @dev Returns `None` for unprocessed contexts and claimable records; read processed/idPlusOne too.
    function holderApexSkipReasonByContext(uint256 contextId) external view returns (HolderApexSkipReason);
    function totalTrackedWeth() external view returns (uint256);
    function holderApexById(uint256 apexId) external view returns (HolderApex memory);
    function holderApexByContextId(uint256 contextId) external view returns (HolderApex memory);
    function recordSwapFee(uint256 totalFeeWeth) external;
    function claimTreasuryWeth() external returns (uint256 claimedWeth);
    function notifyEligibleExactInputBuy() external returns (BuybackNotificationResult result);
    function claimBuybackWeth(uint256 requestedWeth) external returns (uint256 claimedWeth);
    function recordBuybackExecution(uint256 spentWeth, uint256 tokenBurned) external;
    function reserveApexPayout(uint256 buybackWeth, uint256 holderWeth) external;
    function reserveApexPayoutWithHolderRecord(uint256 buybackWeth, uint256 holderWeth, uint256 contextId)
        external
        returns (bool holderApexCreated, uint256 holderApexId);
    function claim(uint256 maxApexes) external returns (uint256 paidWeth, uint256 processedApexes);
    function claimTo(address recipient, uint256 maxApexes) external returns (uint256 paidWeth, uint256 processedApexes);
    function clearBuybackDue() external;
}
