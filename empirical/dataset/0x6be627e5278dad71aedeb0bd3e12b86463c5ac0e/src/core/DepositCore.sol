// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {PlanManager} from "./PlanManager.sol";
import {ErrorsLib} from "../libs/ErrorsLib.sol";
import {EventsLib} from "../libs/EventsLib.sol";
import {StakingTypes} from "../libs/StakingTypes.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title  DepositCore
 * @notice Internal logic layer for the CoinBank staking system.
 *
 *         All staking operations are implemented here as `internal` functions.
 *         No function in this contract is exposed externally; the concrete
 *         entry-point contracts (CoinBankDeposit, CargoDeposit) wrap each helper
 *         with the appropriate visibility, modifiers, and access control.
 */
abstract contract DepositCore is PlanManager {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    /**
     * @dev Opens a new staking position on behalf of `depositor`.
     *
     *      The caller passes the desired `lockDuration`; the system looks up an
     *      owner-configured plan whose duration matches exactly. If no active plan
     *      exists for that duration the call reverts with {NoPlanForDuration}.
     *      Only durations that correspond to a configured plan are accepted —
     *      there is no arbitrary free-form lock period.
     *
     * @param depositId    Off-chain deposit identifier supplied by the backend. Must be unique.
     * @param token        Address of the ERC-20 token to deposit.
     * @param amount       Number of tokens to lock (in the token's native decimals).
     * @param lockDuration Desired lock period in seconds. Must exactly match an active plan's duration.
     * @param depositor    Address whose tokens are pulled and whose position is recorded.
     */
    function _deposit(bytes32 depositId, address token, uint256 amount, uint256 lockDuration, address depositor)
        internal
    {
        _requireNonZeroDepositId(depositId);
        _requireNonZeroTokenAddress(token);
        _requireAuthorizedToken(_authorizedTokens[token], token);
        _requireNonZeroAmount(amount);
        _requireDepositIdUnused(_deposits[depositId].depositedAt, depositId);

        StakingTypes.Plan memory plan = _resolvePlan(lockDuration);
        uint256 profitRateBps = plan.profitRateBps;
        uint256 profit = _calculateProfit(amount, profitRateBps, lockDuration);

        // Reserve check: ensure contract has enough unreserved tokens to cover profit.
        // The incoming principal is NOT counted yet — it arrives at the end of this function.
        uint256 contractBalance = IERC20(token).balanceOf(address(this));
        uint256 currentReserved = _reservedProfit[token] + _lockedPrincipal[token];
        uint256 availableForReserve = contractBalance > currentReserved ? contractBalance - currentReserved : 0;

        if (availableForReserve < profit) {
            revert ErrorsLib.InsufficientReserveForProfit(token, profit, availableForReserve);
        }

        uint256 depositedAt = block.timestamp;
        uint256 unlocksAt = depositedAt + lockDuration;

        _deposits[depositId] = StakingTypes.Deposit({
            depositId: depositId,
            depositor: depositor,
            token: token,
            principal: amount,
            profit: profit,
            profitRateBps: profitRateBps,
            lockDuration: lockDuration,
            depositedAt: depositedAt,
            unlocksAt: unlocksAt,
            status: StakingTypes.DepositStatus.Active,
            profitWithdrawn: 0
        });

        // ── Update reserves ──
        _reservedProfit[token] += profit;
        _lockedPrincipal[token] += amount;
        _activeDepositIds.add(depositId);

        IERC20(token).safeTransferFrom(depositor, address(this), amount);

        emit EventsLib.DepositCreated(depositId, depositor, token, amount, profit, lockDuration, unlocksAt);
    }

    /**
     * @dev Withdraws the profit that has accrued based on complete months elapsed.
     *
     *      Profit accrues discretely per complete month:
     *        accrued = totalProfit * completeMonthsElapsed / totalMonths
     *
     *      Partial months do not count. Only the delta since the last claim is
     *      transferred, so this function can be called multiple times during the
     *      lock period.
     *
     * @param depositId Off-chain deposit identifier of the position.
     * @param caller    Address requesting the profit; must match the depositor.
     */
    function _withdrawProfit(bytes32 depositId, address caller) internal {
        StakingTypes.Deposit storage dep = _deposits[depositId];

        _requireDepositExists(dep.depositedAt, depositId);
        _requireIsDepositor(dep.depositor, caller);
        _requireNotWithdrawn(dep.status);

        // ── Discrete monthly accrual ───────────────────────────────────────
        // Only complete months count. Partial months are truncated.
        uint256 elapsed = block.timestamp - dep.depositedAt;
        if (elapsed > dep.lockDuration) elapsed = dep.lockDuration;

        // Calculate complete months elapsed and total months in lock period
        uint256 completeMonths = elapsed / MONTH;
        uint256 totalMonths = dep.lockDuration / MONTH;

        // accrued = totalProfit * completeMonths / totalMonths
        uint256 accrued = (dep.profit * completeMonths) / totalMonths;

        // due = newly accrued portion not yet paid out
        uint256 due = accrued - dep.profitWithdrawn;
        if (due == 0) revert ErrorsLib.NoProfitAccrued();

        // Sanity-check: contract must hold enough tokens.
        uint256 contractBalance = IERC20(dep.token).balanceOf(address(this));
        if (contractBalance < due) revert ErrorsLib.InsufficientContractBalance(due, contractBalance);

        // ── State update before transfer (checks-effects-interactions) ────────
        dep.profitWithdrawn += due;

        // ── Release from reserve ──
        _reservedProfit[dep.token] -= due;

        // ── Interaction ───────────────────────────────────────────────────────────
        _handleTransferTokens(dep.token, dep.depositor, due);

        emit EventsLib.ProfitWithdrawn(depositId, dep.depositor, dep.token, due);
    }

    /**
     * @dev Withdraws remaining principal + all unclaimed profit after the lock matures.
     * @param depositId Off-chain deposit identifier of the position to withdraw.
     * @param caller    Address requesting the withdrawal; must match the depositor (or keeper).
     */
    function _withdraw(bytes32 depositId, address caller) internal {
        StakingTypes.Deposit storage dep = _deposits[depositId];

        _requireDepositExists(dep.depositedAt, depositId);
        if (caller != keeper) _requireIsDepositor(dep.depositor, caller);
        _requireNotWithdrawn(dep.status);
        _requireLockExpired(dep.unlocksAt);

        // Remaining principal + all unclaimed profit.
        uint256 remainProfit = dep.profit - dep.profitWithdrawn;
        uint256 totalPayout = dep.principal + remainProfit;

        // Sanity-check: contract must hold enough tokens to cover the payout.
        uint256 contractBalance = IERC20(dep.token).balanceOf(address(this));
        if (contractBalance < totalPayout) {
            revert ErrorsLib.InsufficientContractBalance(totalPayout, contractBalance);
        }

        // ── Release from reserves ──
        _reservedProfit[dep.token] -= remainProfit;
        _lockedPrincipal[dep.token] -= dep.principal;

        // remove from active deposits set
        _activeDepositIds.remove(depositId);

        dep.status = StakingTypes.DepositStatus.Withdrawn;

        IERC20(dep.token).safeTransfer(dep.depositor, totalPayout);

        emit EventsLib.Withdrawn(depositId, dep.depositor, dep.principal, remainProfit, totalPayout);
    }

    /**
     * @dev Internal helper to transfer tokens from the contract to a recipient.
     * @param token  Address of the ERC-20 token to transfer.
     * @param to     Recipient address.
     * @param amount Amount of tokens to transfer (in the token's native decimals).
     */
    function _handleTransferTokens(address token, address to, uint256 amount) internal {
        IERC20(token).safeTransfer(to, amount);
    }

    /**
     * @dev Computes the profit that has accrued up to now but has not yet been claimed.
     *      Returns 0 for unknown or already-withdrawn deposits.
     *      Only complete months count — partial months are not included.
     */
    function _previewAccruedProfit(bytes32 depositId) internal view returns (uint256 claimable) {
        StakingTypes.Deposit storage dep = _deposits[depositId];
        if (dep.depositedAt == 0) return 0;
        if (dep.status == StakingTypes.DepositStatus.Withdrawn) return 0;

        uint256 elapsed = block.timestamp - dep.depositedAt;
        if (elapsed > dep.lockDuration) elapsed = dep.lockDuration;

        // Discrete monthly accrual: only complete months count
        uint256 completeMonths = elapsed / MONTH;
        uint256 totalMonths = dep.lockDuration / MONTH;

        uint256 accrued = (dep.profit * completeMonths) / totalMonths;
        return accrued > dep.profitWithdrawn ? accrued - dep.profitWithdrawn : 0;
    }

    /**
     * @dev Returns the full deposit record for a given deposit identifier.
     *      Returns a zero-initialised struct when the deposit does not exist.
     */
    function _getDeposit(bytes32 depositId) internal view returns (StakingTypes.Deposit memory) {
        return _deposits[depositId];
    }

    /**
     * @dev Computes the total payout (principal + remaining profit) without state changes.
     *      Reverts with {DepositNotFound} when `depositId` is unknown.
     */
    function _previewPayout(bytes32 depositId) internal view returns (uint256 totalPayout) {
        StakingTypes.Deposit storage dep = _deposits[depositId];
        if (dep.depositedAt == 0) revert ErrorsLib.DepositNotFound(depositId);
        return dep.principal + (dep.profit - dep.profitWithdrawn);
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Reserve management
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @dev Returns the total reserved profit for a given token.
     *      This amount must remain in the contract to cover future profit payouts.
     */
    function _getReservedProfit(address token) internal view returns (uint256) {
        return _reservedProfit[token];
    }

    /**
     * @dev Returns the total locked principal for a given token.
     *      This amount belongs to active deposits and cannot be withdrawn by the owner.
     */
    function _getLockedPrincipal(address token) internal view returns (uint256) {
        return _lockedPrincipal[token];
    }

    /**
     * @dev Returns the total reserved amount (profit + principal) for a given token.
     */
    function _getTotalReserved(address token) internal view returns (uint256) {
        return _reservedProfit[token] + _lockedPrincipal[token];
    }

    /**
     * @dev Returns the amount of tokens that can be rescued by the owner for a given token.
     *      This is the contract balance minus all reserved amounts.
     */
    function _getRescuableAmount(address token) internal view returns (uint256) {
        uint256 balance = IERC20(token).balanceOf(address(this));
        uint256 reserved = _getTotalReserved(token);
        return balance > reserved ? balance - reserved : 0;
    }
}
