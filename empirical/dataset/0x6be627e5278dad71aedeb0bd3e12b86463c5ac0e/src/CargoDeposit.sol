// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {DepositCore} from "./core/DepositCore.sol";
import {StakingTypes} from "./libs/StakingTypes.sol";
import {EventsLib} from "./libs/EventsLib.sol";
import {ErrorsLib} from "./libs/ErrorsLib.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title  CargoDeposit
 * @author CoinBank
 * @notice Top-level entry point for the CargoDeposit token staking / deposit system.
 *
 *         Users select a fixed-duration plan by its planId. The lock duration and
 *         profit rate are determined entirely by the plan — no arbitrary duration
 *         is accepted. Early withdrawal is not supported.
 */
contract CargoDeposit is DepositCore, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    /**
     * @notice Deploys the contract, transfers ownership to `initialOwner`.
     * @param initialOwner Address that will receive `Ownable` ownership.
     */
    constructor(address initialOwner) Ownable(initialOwner) {}

    // ------------------- Owner functions -------------------

    /**
     * @notice Adds `token` to the staking whitelist, allowing users to deposit with it.
     * @param token Address of the ERC-20 token to authorize.
     */
    function authorizeToken(address token) external onlyOwner {
        _requireNonZeroTokenAddress(token);
        _authorizedTokens[token] = true;
        emit EventsLib.TokenAuthorized(token);
    }

    /**
     * @notice Removes `token` from the staking whitelist.
     *         Existing deposits in this token are unaffected; only new deposits are blocked.
     * @param token Address of the ERC-20 token to revoke.
     */
    function revokeToken(address token) external onlyOwner {
        _requireNonZeroTokenAddress(token);
        _authorizedTokens[token] = false;
        emit EventsLib.TokenRevoked(token);
    }

    /**
     * @notice Replaces the entire set of staking plans in a single transaction.
     * @param plans Array of fixed-duration plan definitions to install.
     *              All installed plans start as active; `active` field on input is ignored.
     */
    function setupPlans(StakingTypes.Plan[] calldata plans) external onlyOwner {
        _setupPlans(plans);
    }

    /**
     * @notice Adds a new fixed-duration staking plan.
     * @param duration      Exact lock duration in seconds (e.g. 30 days, 90 days, 180 days).
     *                      Must be > 0 and ideally a multiple of 30 days.
     * @param profitRateBps Per-month profit rate in basis points (100 bps = 1 % / month).
     */
    function addPlan(uint256 duration, uint256 profitRateBps) external onlyOwner {
        _addPlan(duration, profitRateBps);
    }

    /**
     * @notice Updates an existing fixed-duration staking plan.
     * @param planId        Index of the plan to update.
     * @param duration      New exact lock duration in seconds (must be > 0).
     * @param profitRateBps New per-month profit rate in basis points.
     * @param active        Set to false to prevent new deposits from selecting this plan.
     */
    function updatePlan(uint256 planId, uint256 duration, uint256 profitRateBps, bool active) external onlyOwner {
        _updatePlan(planId, duration, profitRateBps, active);
    }

    /**
     * @notice Sets the keeper address. The keeper can call withdrawAll on behalf of users.
     * @param newKeeper Address of the new keeper. Cannot be the zero address.
     */
    function setKeeper(address newKeeper) external onlyOwner {
        if (newKeeper == address(0)) revert ErrorsLib.InvalidKeeperAddress();
        keeper = newKeeper;
    }

    /**
     * @notice Sends `amount` of `token` from the contract to the owner.
     *         Capped at the rescuable balance (contract balance minus all reserves).
     * @param token  Address of the ERC-20 token to withdraw.
     * @param amount Amount of tokens to withdraw (in the token's native decimals).
     */
    function rescueTokens(address token, uint256 amount) external onlyOwner {
        uint256 rescuable = _getRescuableAmount(token);
        if (amount > rescuable) {
            revert ErrorsLib.ExceedsRescuableAmount(token, amount, rescuable);
        }
        _handleTransferTokens(token, owner(), amount);
    }

    // ------------------- User functions -------------------

    /**
     * @notice Opens a new staking position.
     * @param depositId    Off-chain deposit identifier (bytes32) supplied by the backend.
     *                     Must be unique — reusing an id reverts.
     * @param token        Address of the ERC-20 token to deposit.
     * @param amount       Number of tokens to lock (in the token's native decimals).
     * @param lockDuration Desired lock period in seconds. Must exactly match a configured active plan
     *                     (e.g. 30 days, 90 days, 180 days, 360 days). Any other value reverts.
     */
    function deposit(bytes32 depositId, address token, uint256 amount, uint256 lockDuration) external nonReentrant {
        _deposit(depositId, token, amount, lockDuration, msg.sender);
    }

    /**
     * @notice Withdraws the profit accrued up to this moment for a staking position.
     *         Only complete months count; partial months are not paid out.
     * @param depositId Off-chain deposit identifier of the position.
     */
    function withdrawProfit(bytes32 depositId) external nonReentrant {
        _withdrawProfit(depositId, msg.sender);
    }

    /**
     * @notice Withdraws the principal (plus any unclaimed profit) for a matured position.
     * @param depositId Off-chain deposit identifier of the position to withdraw.
     */
    function withdrawAll(bytes32 depositId) external nonReentrant {
        _withdraw(depositId, msg.sender);
    }

    // ------------------- View functions -------------------

    /**
     * @notice Returns the total number of plans ever created (including inactive ones).
     */
    function planCount() external view returns (uint256) {
        return _planCount();
    }

    /**
     * @notice Returns the plan struct at a given index.
     * @param planId Index of the plan.
     */
    function getPlan(uint256 planId) external view returns (StakingTypes.Plan memory) {
        return _getPlan(planId);
    }

    /**
     * @notice Returns the total reserved profit for a given token.
     * @param token Address of the ERC-20 token to query.
     */
    function getReservedProfit(address token) external view returns (uint256) {
        return _getReservedProfit(token);
    }

    /**
     * @notice Returns the total locked principal for a given token.
     * @param token Address of the ERC-20 token to query.
     */
    function getLockedPrincipal(address token) external view returns (uint256) {
        return _getLockedPrincipal(token);
    }

    /**
     * @notice Returns the total reserved amount (profit + principal) for a given token.
     * @param token Address of the ERC-20 token to query.
     */
    function getTotalReserved(address token) external view returns (uint256) {
        return _getTotalReserved(token);
    }

    /**
     * @notice Returns the amount of tokens that can be rescued by the owner.
     * @param token Address of the ERC-20 token to query.
     */
    function getRescuableAmount(address token) external view returns (uint256) {
        return _getRescuableAmount(token);
    }

    /**
     * @notice Returns the full deposit record for a given deposit identifier.
     * @param depositId The off-chain deposit identifier to query.
     */
    function getDeposit(bytes32 depositId) external view returns (StakingTypes.Deposit memory) {
        return _getDeposit(depositId);
    }

    /**
     * @notice Returns the profit amount claimable right now for a given position.
     * @param depositId The off-chain deposit identifier to query.
     */
    function previewAccruedProfit(bytes32 depositId) external view returns (uint256 claimable) {
        return _previewAccruedProfit(depositId);
    }

    /**
     * @notice Computes the total payout (principal + remaining profit) for a deposit.
     * @param depositId The off-chain deposit identifier to query.
     */
    function previewPayout(bytes32 depositId) external view returns (uint256 totalPayout) {
        return _previewPayout(depositId);
    }

    /**
     * @notice Returns the total number of active (non-withdrawn) deposits.
     */
    function getActiveDepositCount() external view returns (uint256) {
        return _activeDepositIds.length();
    }

    /**
     * @notice Returns the deposit ID at the given index in the active deposits set.
     * @param index Zero-based index into the active deposits set.
     */
    function getActiveDepositIdAt(uint256 index) external view returns (bytes32) {
        return _activeDepositIds.at(index);
    }

    /**
     * @notice Returns all active deposit IDs.
     * @dev WARNING: Expensive for large sets. Prefer getActiveDepositCount + getActiveDepositIdAt.
     */
    function getAllActiveDepositIds() external view returns (bytes32[] memory) {
        return _activeDepositIds.values();
    }
}
