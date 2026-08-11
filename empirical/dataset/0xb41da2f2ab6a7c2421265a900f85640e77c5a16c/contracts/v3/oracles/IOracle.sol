// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Textile, Inc.
pragma solidity 0.8.30;

/**
 * @title IOracle
 * @notice Generic price oracle interface consumed by SettlementPool at open() time.
 * @dev Implementations: PushOracle (admin-pushed P2P-aggregated rates), and future
 *      adapters (ChainlinkAdapter, MentoAdapter, PythAdapter). Each pool wires to its
 *      own implementation via factory-deploy constructor arg.
 *
 *      Oracle rates are `collateral units per 1 debt unit` in RAY (1e27)
 *      precision. `buyRate()` is the executable side SettlementPool uses at
 *      open(): `C = D * buyRate * (1 + buffer)`. `sellRate()` is the opposite
 *      executable side used by reverse-direction adapters and off-chain consumers.
 */
interface IOracle {
  /**
   * @notice Latest valid buy-side rate, scaled to RAY (1e27).
   * @dev Implementations MUST revert when paused. Same-block-as-update reads MUST
   *      revert for non-admin readers (sandwich-protection).
   * @return rateRay Buy-side rate in collateral-units-per-debt-unit, RAY-scaled.
   */
  function buyRate() external view returns (uint256 rateRay);

  /**
   * @notice Latest valid sell-side rate, scaled to RAY (1e27).
   * @dev Implementations MUST apply the same pause/freshness/same-block
   *      semantics as `buyRate()`.
   * @return rateRay Sell-side rate in collateral-units-per-debt-unit, RAY-scaled.
   */
  function sellRate() external view returns (uint256 rateRay);

  /**
   * @notice True if the oracle is paused (stale, deviation, or cumulative-bound trip).
   * @return paused_ Whether rate reads will revert.
   */
  function paused() external view returns (bool paused_);
}
