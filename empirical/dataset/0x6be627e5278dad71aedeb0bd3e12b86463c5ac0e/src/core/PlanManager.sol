// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from "../../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

import {DepositStorage} from "./DepositStorage.sol";
import {DepositValidator} from "./DepositValidator.sol";
import {ErrorsLib} from "../libs/ErrorsLib.sol";
import {EventsLib} from "../libs/EventsLib.sol";
import {StakingTypes} from "../libs/StakingTypes.sol";

/**
 * @title  PlanManager
 * @notice Owner-only module for managing fixed-duration staking plan tiers.
 *
 *         Each plan defines an exact lock duration and a per-month profit rate.
 *         Users select a plan by its index (planId) — no arbitrary duration is accepted.
 *
 *         Example plans:
 *           planId 0 → 1 month  (30 days)  → 1.0 % / month (100 bps)
 *           planId 1 → 3 months (90 days)  → 1.2 % / month (120 bps)
 *           planId 2 → 6 months (180 days) → 1.5 % / month (150 bps)
 *           planId 3 → 12 months (360 days)→ 2.0 % / month (200 bps)
 */
abstract contract PlanManager is Ownable, DepositStorage, DepositValidator {
    /**
     * @dev Adds a new fixed-duration staking plan.
     * @param duration      Exact lock duration in seconds (must be > 0 and a multiple of 30 days).
     * @param profitRateBps Per-month profit rate in basis points (100 bps = 1 % / month).
     */
    function _addPlan(uint256 duration, uint256 profitRateBps) internal {
        if (duration == 0) revert ErrorsLib.ZeroLockDuration();

        uint256 planId = _plans.length;
        _plans.push(StakingTypes.Plan({duration: duration, profitRateBps: profitRateBps, active: true}));

        emit EventsLib.PlanAdded(planId, duration, profitRateBps);
    }

    /**
     * @dev Updates all fields of an existing fixed-duration plan.
     * @param planId        Index of the plan to update.
     * @param duration      New exact lock duration in seconds (must be > 0).
     * @param profitRateBps New per-month profit rate in basis points.
     * @param active        Set to false to prevent new deposits from selecting this plan.
     */
    function _updatePlan(uint256 planId, uint256 duration, uint256 profitRateBps, bool active) internal {
        _requirePlanExists(planId, _plans.length);
        if (duration == 0) revert ErrorsLib.ZeroLockDuration();

        StakingTypes.Plan storage plan = _plans[planId];
        plan.duration = duration;
        plan.profitRateBps = profitRateBps;
        plan.active = active;

        emit EventsLib.PlanUpdated(planId, duration, profitRateBps, active);
    }

    /**
     * @dev Replaces the entire plan list with the supplied array.
     *      All existing plans are removed; each entry in `plans` is pushed as a new active plan.
     *      Emits {PlanAdded} for every installed plan.
     * @param plans Array of plan definitions. May be empty to clear all plans.
     */
    function _setupPlans(StakingTypes.Plan[] calldata plans) internal {
        delete _plans;

        uint256 len = plans.length;
        for (uint256 i; i < len; ++i) {
            if (plans[i].duration == 0) revert ErrorsLib.ZeroLockDuration();

            _plans.push(
                StakingTypes.Plan({duration: plans[i].duration, profitRateBps: plans[i].profitRateBps, active: true})
            );

            emit EventsLib.PlanAdded(i, plans[i].duration, plans[i].profitRateBps);
        }
    }

    /**
     * @dev Returns the total number of plans ever created (including inactive ones).
     */
    function _planCount() internal view returns (uint256) {
        return _plans.length;
    }

    /**
     * @dev Returns the plan struct at a given index. Reverts if out of range.
     */
    function _getPlan(uint256 planId) internal view returns (StakingTypes.Plan memory) {
        _requirePlanExists(planId, _plans.length);
        return _plans[planId];
    }

    /**
     * @dev Finds and returns the active plan whose duration matches `lockDuration` exactly.
     *      Reverts with {NoPlanForDuration} when no active plan has that exact duration.
     *
     *      This is the deposit-path resolver: users specify the lock duration they want,
     *      and the system checks whether an owner-configured plan exists for it.
     *
     * @param lockDuration Lock duration in seconds to look up (exact match).
     */
    function _resolvePlan(uint256 lockDuration) internal view returns (StakingTypes.Plan memory) {
        uint256 len = _plans.length;
        for (uint256 i; i < len; ++i) {
            StakingTypes.Plan storage plan = _plans[i];
            if (plan.active && plan.duration == lockDuration) {
                return plan;
            }
        }
        revert ErrorsLib.NoPlanForDuration(lockDuration);
    }

    /**
     * @dev Calculates the total profit for a position at maturity.
     *
     *      Formula:  profit = principal × profitRateBps × lockDuration
     *                         ─────────────────────────────────────────
     *                              BPS_DENOMINATOR × 30 days
     *
     *      `profitRateBps` is a per-month rate where 1 month = 30 days.
     *      For exact amounts `lockDuration` should be a whole-number multiple of 30 days.
     *
     * @param principal     Amount of tokens deposited.
     * @param profitRateBps Per-month profit rate in basis points (100 bps = 1 % / month).
     * @param lockDuration  Lock period in seconds. Should be a multiple of 30 days.
     * @return profit       Total profit claimable at maturity.
     */
    function _calculateProfit(uint256 principal, uint256 profitRateBps, uint256 lockDuration)
        internal
        pure
        returns (uint256 profit)
    {
        profit = (principal * profitRateBps * lockDuration) / (BPS_DENOMINATOR * MONTH);
    }
}
