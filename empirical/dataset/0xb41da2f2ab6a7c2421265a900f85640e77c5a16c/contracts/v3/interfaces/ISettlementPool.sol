// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Textile, Inc.
// This smart contract is part of the Textile Protocol (Settlement v3).
pragma solidity 0.8.30;

/**
 * @title ISettlementPool
 * @notice External integrator interface for SettlementPool. Mirrors the v2.1 layout
 *         (`interfaces/`). Factory deploys SettlementPool concretely; closers and
 *         the closer-bot can typecast pool addresses through this interface.
 */
interface ISettlementPool {
  // ---------- mutating ----------
  function deposit(uint256 assets, address receiver) external returns (uint256 cohortId, uint256 units);
  function redeem(uint256 cohortId, uint256 units, address receiver) external returns (uint256 assets);
  function open(uint256 D) external returns (uint256 id);
  function fill(uint256 maxDebtIn, uint256 maxPositions)
    external
    returns (uint256 positionsFilled, uint256 debtInUsed, uint256 collateralOut);
  function claimYield(uint256[] calldata cohortIds) external returns (uint256 amount);
  function claimPendingRefund() external returns (uint256 amount);

  // ---------- views ----------
  function asset() external view returns (address);
  function totalAssets() external view returns (uint256);
  function balanceOf(address user, uint256 cohortId) external view returns (uint256);
  function maxRedeem(address user, uint256 cohortId) external view returns (uint256);
  function maxWithdraw(address user, uint256 cohortId) external view returns (uint256);
  function claimableYield(address user, uint256 cohortId) external view returns (uint256);
}
