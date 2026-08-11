// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Textile, Inc.
// This smart contract is part of the Textile Protocol (Settlement v3).
pragma solidity 0.8.30;

/// @notice Centralized custom errors for Settlement v3 (cross-contract symbols only).
///         Mirrors the v2.1 layout (`libraries/helpers/Errors.sol`). Per-contract
///         single-use errors stay inline in the contract that defines them.
library Errors {
  // Input validation
  error ZeroAmount();
  error ZeroAddress();
  error InvalidPair();
  error InvalidParams();
  error InvalidPrice();
  error BelowMinSize();

  // Pool accounting
  error InsufficientLPCapacity();
  error InsufficientFreeLiquidity();
  error PositionNotFound();
  error ConservationBroken();
  error NothingToFill();
  error FillBudgetTooLow();

  // Access / state
  error NotOwner();
  error OnlySelf();
  error EnforcedPause();
  error RenounceDisabled();

  // Oracle
  error OracleStale();
  error OracleDeviation();
  error OracleCumulativeBound();
  error SameBlockUse();
  error NotPaused();
  error BaselineResetCooldown();

  // Batch
  error BatchTooLarge();
}
