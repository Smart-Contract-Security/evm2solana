// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Textile, Inc.
// This smart contract is part of the Textile Protocol (Settlement v3).
pragma solidity 0.8.30;

/// @notice Per-borrower settlement position record. Packed into 3 storage slots.
///         Mirrors the v2.1 types layout (`libraries/types/`).
library PositionTypes {
  struct Position {
    address borrower; // slot 0: 20 bytes
    uint96 openTime; // slot 0: 12 bytes (32 total)
    uint128 C; // slot 1: 16 bytes (collateral atomic units)
    uint128 D; // slot 1: 16 bytes (debt atomic units, 32 total)
    uint256 rateAtOpen; // slot 2: buy-side RAY-scaled (collateral_atomic / debt_atomic)
  }

  /// @notice Debt funding attribution for one position.
  struct FundingSlice {
    uint256 cohortId;
    uint256 debtAmount;
  }
}
