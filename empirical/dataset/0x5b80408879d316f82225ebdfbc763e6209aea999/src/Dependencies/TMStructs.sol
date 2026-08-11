// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

// Store the necessary data for an interest batch manager. We treat each batch as a "big trove".
// Each trove has a share of the debt of the global batch. Collateral is stored per trove (as CRs are different)
// Still the total amount of batch collateral is stored for informational purposes
struct Batch {
    uint256 debt;
    uint256 coll;
    uint64 arrayIndex;
    uint64 lastDebtUpdateTime;
    uint64 lastInterestRateAdjTime;
    uint256 annualInterestRate;
    uint256 annualManagementFee;
    uint256 totalDebtShares;
}
