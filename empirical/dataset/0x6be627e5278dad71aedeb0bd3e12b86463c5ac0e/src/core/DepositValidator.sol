// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ErrorsLib} from "../libs/ErrorsLib.sol";
import {StakingTypes} from "../libs/StakingTypes.sol";

/**
 * @title  DepositValidator
 * @notice Stateless validation helpers shared across all CoinBank core modules.
 *
 *         Every function is either `pure` or `view` and accepts only the scalar
 *         values it needs — no storage reads happen here.  This keeps the
 *         validation layer fully decoupled from storage layout and easy to unit-test
 *         in isolation.
 */
abstract contract DepositValidator {
    /// @dev Reverts if `depositId` is the zero value.
    function _requireNonZeroDepositId(bytes32 depositId) internal pure {
        if (depositId == bytes32(0)) revert ErrorsLib.ZeroDepositId();
    }

    /// @dev Reverts if `token` is the zero address.
    function _requireNonZeroTokenAddress(address token) internal pure {
        if (token == address(0)) revert ErrorsLib.ZeroTokenAddress();
    }

    /// @dev Reverts if `amount` is zero.
    function _requireNonZeroAmount(uint256 amount) internal pure {
        if (amount == 0) revert ErrorsLib.ZeroAmount();
    }

    /**
     * @dev Reverts if the deposit does not exist.
     *      Existence is indicated by a non-zero `depositedAt` timestamp.
     */
    function _requireDepositExists(uint256 depositedAt, bytes32 depositId) internal pure {
        if (depositedAt == 0) revert ErrorsLib.DepositNotFound(depositId);
    }

    /**
     * @dev Reverts if the deposit id is already in use.
     *      A non-zero `depositedAt` means the slot is occupied.
     */
    function _requireDepositIdUnused(uint256 depositedAt, bytes32 depositId) internal pure {
        if (depositedAt != 0) revert ErrorsLib.DepositIdAlreadyUsed(depositId);
    }

    /**
     * @dev Reverts if `caller` is not the depositor.
     */
    function _requireIsDepositor(address depositor, address caller) internal pure {
        if (depositor != caller) revert ErrorsLib.NotDepositor(caller, depositor);
    }

    /// @dev Reverts if the deposit has already been fully withdrawn.
    function _requireNotWithdrawn(StakingTypes.DepositStatus status) internal pure {
        if (status == StakingTypes.DepositStatus.Withdrawn) revert ErrorsLib.AlreadyWithdrawn();
    }

    /**
     * @dev Reverts if the lock period has NOT yet expired.
     *      Used by the normal withdraw path which requires maturity.
     */
    function _requireLockExpired(uint256 unlocksAt) internal view {
        if (block.timestamp < unlocksAt) revert ErrorsLib.LockPeriodNotExpired(unlocksAt, block.timestamp);
    }

    /**
     * @dev Reverts if `token` is not on the authorized whitelist.
     */
    function _requireAuthorizedToken(bool authorized, address token) internal pure {
        if (!authorized) revert ErrorsLib.TokenNotAuthorized(token);
    }

    /**
     * @dev Reverts if `planId` >= `totalPlans` (i.e. the index is out of range).
     */
    function _requirePlanExists(uint256 planId, uint256 totalPlans) internal pure {
        if (planId >= totalPlans) revert ErrorsLib.PlanNotFound(planId);
    }
}
