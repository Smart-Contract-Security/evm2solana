// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title  StakingTypes
 * @notice Shared data structures and enumerations used across the CoinBank staking system.
 */
library StakingTypes {
    /**
     * @notice Lifecycle states of a deposit position.
     */
    enum DepositStatus {
        Active, // Funds are locked; lock period has not yet expired.
        Withdrawn // Principal + profit have been claimed by the depositor.
    }

    /**
     * @notice Defines a fixed-duration staking plan configured by the contract owner.
     *         Users select a plan by its index (planId) — no arbitrary duration is accepted.
     * @param duration      Exact lock duration in seconds (e.g. 30 days = 1 month).
     * @param profitRateBps Per-month profit rate in basis points (100 bps = 1 % / month).
     * @param active        Whether this plan is currently accepting new deposits.
     */
    struct Plan {
        uint256 duration;
        uint256 profitRateBps;
        bool active;
    }

    /**
     * @notice Records a single user deposit / staking position.
     *
     * @param depositId       Off-chain deposit identifier supplied by the backend.
     * @param depositor       Address that created the position.
     * @param token           ERC-20 token contract address deposited.
     * @param principal       Principal amount locked.
     * @param profit          Total profit claimable at maturity.
     * @param profitRateBps   Snapshotted profit rate (bps) from the matched plan.
     * @param lockDuration    Lock duration in seconds taken from the selected plan.
     * @param depositedAt     Block timestamp when the deposit was created.
     * @param unlocksAt       Block timestamp when the principal matures.
     * @param status          Current lifecycle state of this position.
     * @param profitWithdrawn Cumulative profit paid out via withdrawProfit().
     */
    struct Deposit {
        bytes32 depositId;
        address depositor;
        address token;
        uint256 principal;
        uint256 profit;
        uint256 profitRateBps;
        uint256 lockDuration;
        uint256 depositedAt;
        uint256 unlocksAt;
        DepositStatus status;
        uint256 profitWithdrawn;
    }
}
