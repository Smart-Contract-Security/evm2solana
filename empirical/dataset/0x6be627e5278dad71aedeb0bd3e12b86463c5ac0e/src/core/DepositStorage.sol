// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {StakingTypes} from "../libs/StakingTypes.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title  DepositStorage
 * @notice Defines the canonical storage layout for the CoinBank staking system.
 *
 *         All state variables are declared here so that PlanManager and
 *         DepositCore share the exact same storage slots without risk of
 *         collisions across the inheritance chain.
 *
 * @dev    This contract must appear first in the inheritance list of
 *         CoinBankDeposit / CargoDeposit and every logic module that reads or writes state.
 */
abstract contract DepositStorage {
    /**
     * @notice Address of the keeper contract responsible for automated withdrawals.
     */
    address public keeper;

    /**
     * @dev Basis-point denominator: 10 000 bps = 100 %.
     */
    uint256 internal constant BPS_DENOMINATOR = 10_000;

    /**
     * @dev One month duration in seconds (30 days).
     */
    uint256 internal constant MONTH = 30 days;

    /**
     * @notice Ordered list of all fixed-duration staking plans (including inactive ones).
     *         Plans are never deleted; deactivating a plan sets `active = false`.
     *         Users select a plan by its index (planId) — no arbitrary lock duration is accepted.
     */
    StakingTypes.Plan[] internal _plans;

    /**
     * @notice Maps an off-chain deposit identifier to its on-chain deposit record.
     *         A non-zero `depositedAt` value is the canonical existence check.
     */
    mapping(bytes32 depositId => StakingTypes.Deposit) internal _deposits;

    /**
     * @notice Set of depositIds that are currently active (not fully withdrawn).
     *         Used for efficient iteration by the keeper.
     */
    EnumerableSet.Bytes32Set internal _activeDepositIds;

    /**
     * @notice Whitelist of ERC-20 tokens that are permitted for staking.
     *         Only tokens explicitly authorized by the owner can be used in deposits.
     */
    mapping(address token => bool) internal _authorizedTokens;

    /**
     * @notice Total reserved profit per token that must remain in the contract
     *         to cover future profit payouts to depositors.
     */
    mapping(address token => uint256) internal _reservedProfit;

    /**
     * @notice Total locked principal per token that belongs to active deposits.
     *         This amount cannot be withdrawn by the owner via rescueTokens.
     */
    mapping(address token => uint256) internal _lockedPrincipal;
}
