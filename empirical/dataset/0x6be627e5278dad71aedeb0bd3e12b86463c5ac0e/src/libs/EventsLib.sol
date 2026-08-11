// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title  EventsLib
 * @notice All events emitted by the CoinBank deposit / staking system.
 *         Centralising events in one library makes indexing and ABI management easier.
 */
library EventsLib {
    // ─────────────────────────────────────────────────────────────────────────
    //  Plan events
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Emitted when the owner adds a new staking plan.
     * @param planId        Index of the newly created plan in the plans array.
     * @param duration      Exact lock duration in seconds.
     * @param profitRateBps Per-month profit rate in basis points.
     */
    event PlanAdded(uint256 planId, uint256 duration, uint256 profitRateBps);

    /**
     * @notice Emitted when the owner updates an existing staking plan.
     * @param planId        Index of the updated plan.
     * @param duration      New exact lock duration in seconds.
     * @param profitRateBps New per-month profit rate in basis points.
     * @param active        Whether the plan is now accepting deposits.
     */
    event PlanUpdated(uint256 planId, uint256 duration, uint256 profitRateBps, bool active);

    // ─────────────────────────────────────────────────────────────────────────
    //  Token authorization events
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Emitted when the owner adds a token to the staking whitelist.
     * @param token Address of the authorized ERC-20 token.
     */
    event TokenAuthorized(address token);

    /**
     * @notice Emitted when the owner removes a token from the staking whitelist.
     * @param token Address of the revoked ERC-20 token.
     */
    event TokenRevoked(address token);

    // ─────────────────────────────────────────────────────────────────────────
    //  Deposit events
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Emitted when a user successfully opens a new deposit position.
     * @param depositId    Off-chain identifier supplied by the backend.
     * @param depositor    Address that created the position.
     * @param token        ERC-20 token deposited.
     * @param principal    Amount of tokens locked.
     * @param profit       Pre-calculated profit amount claimable at maturity.
     * @param lockDuration Lock duration in seconds taken from the selected plan.
     * @param unlocksAt    Timestamp at which the position matures.
     */
    event DepositCreated(
        bytes32 depositId,
        address depositor,
        address token,
        uint256 principal,
        uint256 profit,
        uint256 lockDuration,
        uint256 unlocksAt
    );

    /**
     * @notice Emitted when a depositor successfully withdraws principal + profit after maturity.
     * @param depositId   Off-chain identifier of the withdrawn position.
     * @param depositor   Address that received the funds.
     * @param principal   Principal amount returned.
     * @param profit      Profit amount returned (0 if already claimed separately).
     * @param totalPayout Total tokens transferred.
     */
    event Withdrawn(bytes32 depositId, address depositor, uint256 principal, uint256 profit, uint256 totalPayout);

    /**
     * @notice Emitted when a depositor withdraws accrued profit before lock expiry.
     * @param depositId Off-chain identifier of the position.
     * @param depositor Address that received the profit.
     * @param token     ERC-20 token transferred.
     * @param profit    Profit amount paid out.
     */
    event ProfitWithdrawn(bytes32 depositId, address depositor, address token, uint256 profit);
}
