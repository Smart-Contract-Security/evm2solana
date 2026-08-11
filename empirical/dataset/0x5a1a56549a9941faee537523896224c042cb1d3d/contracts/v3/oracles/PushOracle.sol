// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Textile, Inc.
pragma solidity 0.8.30;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IOracle } from "./IOracle.sol";
import { Errors } from "../libraries/helpers/Errors.sol";
import { MathUtils } from "../../v2.1/libraries/math/MathUtils.sol";

/**
 * @title PushOracle
 * @notice Admin-pushed price receiver for emerging-market corridors with no Chainlink
 *         feed (e.g. cNGN/USDT, KES/USDT, COP/USDT). Off-chain aggregator (Inngest job)
 *         computes executable buy/sell sides across multiple sources, then
 *         pushes the smoothed values here via update().
 *
 * @dev Defenses against admin-key compromise (Codex review):
 *
 *      D-1: Per-update deviation breaker. Any buy or sell push deviating
 *           > MAX_DEVIATION_BPS from the previous side-specific price reverts
 *           and leaves the last accepted prices unchanged.
 *
 *      D-2: Cumulative-24h-movement bound. Absolute drift between the latest
 *           accepted price and the rolling-24h baseline must not exceed
 *           MAX_CUMULATIVE_BPS of that baseline. Defends against "walk-the-price"
 *           attacks staying under the per-update breaker by compounding small steps.
 *
 *      D-3: Same-block sandwich reject. Pool reads in the same block as the
 *           most recent update revert. Forces pool open() to wait at least
 *           one block after a price change.
 *
 *      D-4: Freshness. Rate reads revert if last update is older than MAX_AGE.
 *
 *      Rejected D-1/D-2 updates do not pause reads; they preserve the last
 *      accepted price. pause() is an explicit owner-controlled operational state.
 *
 * @dev Audit standards applied:
 *      - OZ Ownable + onlyOwner modifier (no if-revert auth)
 *      - Custom errors inline (no revert strings)
 *      - All state-changing functions emit events
 *      - Constructor validates all inputs
 *      - Public state vars auto-generate getters
 */
contract PushOracle is IOracle, Ownable {
  /*//////////////////////////////////////////////////////////////
                            CONSTANTS
  //////////////////////////////////////////////////////////////*/

  /// @notice Maximum allowed deviation per individual push (5%).
  uint256 public constant MAX_DEVIATION_BPS = 500;

  /// @notice Maximum cumulative absolute movement over a rolling 24h window (15%).
  uint256 public constant MAX_CUMULATIVE_BPS = 1500;

  /// @notice Rolling window for the cumulative bound.
  uint256 public constant CUMULATIVE_WINDOW = 24 hours;

  /// @notice Stale threshold for rate reads.
  uint256 public constant MAX_AGE = 30 minutes;

  /*//////////////////////////////////////////////////////////////
                          STATE VARIABLES
  //////////////////////////////////////////////////////////////*/

  /// @notice Latest pushed buy-side rate in RAY precision.
  uint256 public lastBuyPriceRay;

  /// @notice Latest pushed sell-side rate in RAY precision.
  uint256 public lastSellPriceRay;

  /// @notice Block number of the last update (same-block reject reference).
  uint256 public lastUpdateBlock;

  /// @notice Timestamp of the last update (freshness reference).
  uint256 public lastUpdateAt;

  /// @notice Buy-side baseline anchor for the cumulative bound; reset by resetBaseline().
  uint256 public baselineBuyPriceRay;

  /// @notice Sell-side baseline anchor for the cumulative bound; reset by resetBaseline().
  uint256 public baselineSellPriceRay;

  /// @notice Timestamp the cumulative window opened.
  uint256 public cumulativeWindowStart;

  /// @notice Absolute drift of the last accepted buy price from `baselineBuyPriceRay`,
  ///         expressed in BPS of the baseline. Compared against MAX_CUMULATIVE_BPS.
  ///         Can decrease when a later push moves the price back toward the baseline.
  uint256 public cumulativeBuyBpsMoved;

  /// @notice Absolute drift of the last accepted sell price from `baselineSellPriceRay`.
  uint256 public cumulativeSellBpsMoved;

  /// @notice Manual pause flag. Reserved for explicit owner pause flows, cleared by owner via unpause().
  bool private _deviationPaused;

  /// @notice Anchor for the `resetBaseline()` cooldown. Seeded at construction
  ///         (audit report-3 M-01) so the CUMULATIVE_WINDOW gate applies from
  ///         deployment, and updated on every successful reset. A compromised
  ///         owner cannot clear the cumulative bound more often than the
  ///         natural 24h window roll (audit L-07).
  uint256 public lastBaselineResetAt;

  /*//////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/

  event PricesUpdated(
    uint256 indexed newBuyPriceRay,
    uint256 indexed newSellPriceRay,
    uint256 oldBuyPriceRay,
    uint256 oldSellPriceRay,
    uint256 buyDeltaBps,
    uint256 sellDeltaBps
  );
  event Paused(address indexed owner);
  event Unpaused(address indexed owner);
  event BaselinesReset(uint256 newBuyBaselinePriceRay, uint256 newSellBaselinePriceRay);

  /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/

  /// @dev See `libraries/helpers/Errors.sol` for the cross-contract error catalog.

  /**
   * @param owner_ Initial owner (Textile multisig). Pushes prices and resets state.
   * @param initialPriceRay Seed price in RAY. Sets both sides and cumulative-window baselines.
   */
  constructor(address owner_, uint256 initialPriceRay) Ownable(owner_) {
    if (initialPriceRay == 0) revert Errors.InvalidPrice();

    lastBuyPriceRay = initialPriceRay;
    lastSellPriceRay = initialPriceRay;
    lastUpdateBlock = block.number;
    lastUpdateAt = block.timestamp;
    baselineBuyPriceRay = initialPriceRay;
    baselineSellPriceRay = initialPriceRay;
    cumulativeWindowStart = block.timestamp;
    // Anchor the resetBaseline() cooldown at deployment so the first manual
    // reset still has to wait CUMULATIVE_WINDOW (audit report-3 M-01).
    lastBaselineResetAt = block.timestamp;

    emit PricesUpdated(initialPriceRay, initialPriceRay, 0, 0, 0, 0);
    emit BaselinesReset(initialPriceRay, initialPriceRay);
  }

  /*//////////////////////////////////////////////////////////////
                           ADMIN WRITES
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Push new buy and sell prices. Reverts if either per-update delta exceeds
   *         MAX_DEVIATION_BPS or the absolute drift from the rolling-24h
   *         baseline would exceed MAX_CUMULATIVE_BPS.
   * @param newBuyPriceRay New buy-side rate in RAY (collateral-units per 1 debt-unit).
   * @param newSellPriceRay New sell-side rate in RAY (collateral-units per 1 debt-unit).
   */
  function update(uint256 newBuyPriceRay, uint256 newSellPriceRay) external onlyOwner {
    _update(newBuyPriceRay, newSellPriceRay);
  }

  function _update(uint256 newBuyPriceRay, uint256 newSellPriceRay) internal {
    if (newBuyPriceRay == 0 || newSellPriceRay == 0) revert Errors.InvalidPrice();

    uint256 oldBuyPriceRay = lastBuyPriceRay;
    uint256 oldSellPriceRay = lastSellPriceRay;
    uint256 buyDeltaBps = _absDeltaBps(newBuyPriceRay, oldBuyPriceRay);
    uint256 sellDeltaBps = _absDeltaBps(newSellPriceRay, oldSellPriceRay);

    // D-1: per-update deviation breaker.
    if (buyDeltaBps > MAX_DEVIATION_BPS || sellDeltaBps > MAX_DEVIATION_BPS) {
      revert Errors.OracleDeviation();
    }

    // D-2: baseline-relative cumulative bound. The rolling 24h window measures
    //      absolute drift from the baseline (not the sum of step deltas), so
    //      compounding small in-band steps cannot walk the price past
    //      MAX_CUMULATIVE_BPS. When the window has elapsed the baseline rolls
    //      forward to the last accepted price.
    if (block.timestamp >= cumulativeWindowStart + CUMULATIVE_WINDOW) {
      cumulativeWindowStart = block.timestamp;
      baselineBuyPriceRay = oldBuyPriceRay;
      baselineSellPriceRay = oldSellPriceRay;
      lastBaselineResetAt = block.timestamp;
    }

    uint256 buyBaselineDriftBps = _absDeltaBps(newBuyPriceRay, baselineBuyPriceRay);
    uint256 sellBaselineDriftBps = _absDeltaBps(newSellPriceRay, baselineSellPriceRay);
    if (buyBaselineDriftBps > MAX_CUMULATIVE_BPS || sellBaselineDriftBps > MAX_CUMULATIVE_BPS) {
      revert Errors.OracleCumulativeBound();
    }

    cumulativeBuyBpsMoved = buyBaselineDriftBps;
    cumulativeSellBpsMoved = sellBaselineDriftBps;
    lastBuyPriceRay = newBuyPriceRay;
    lastSellPriceRay = newSellPriceRay;
    lastUpdateBlock = block.number;
    lastUpdateAt = block.timestamp;

    emit PricesUpdated(
      newBuyPriceRay, newSellPriceRay, oldBuyPriceRay, oldSellPriceRay, buyDeltaBps, sellDeltaBps
    );
  }

  /**
   * @notice Manually pause oracle reads after operational review.
   */
  function pause() external onlyOwner {
    if (_deviationPaused) revert Errors.EnforcedPause();
    _deviationPaused = true;
    emit Paused(msg.sender);
  }

  /**
   * @notice Clear the deviation pause after manual review.
   */
  function unpause() external onlyOwner {
    if (!_deviationPaused) revert Errors.NotPaused();
    _deviationPaused = false;
    emit Unpaused(msg.sender);
  }

  /**
   * @notice Reset the cumulative-window baseline to the current price. Used by owner
   *         after manual review of an extended-trend market move that legitimately
   *         exceeded MAX_CUMULATIVE_BPS.
   * @dev Gated by a CUMULATIVE_WINDOW cooldown (audit L-07): a compromised owner
   *      cannot clear the cumulative bound more often than the natural 24h window
   *      roll, so resetBaseline cannot be used to walk the price faster than the
   *      bound otherwise allows.
   */
  function resetBaseline() external onlyOwner {
    if (block.timestamp < lastBaselineResetAt + CUMULATIVE_WINDOW) {
      revert Errors.BaselineResetCooldown();
    }
    lastBaselineResetAt = block.timestamp;
    baselineBuyPriceRay = lastBuyPriceRay;
    baselineSellPriceRay = lastSellPriceRay;
    cumulativeWindowStart = block.timestamp;
    cumulativeBuyBpsMoved = 0;
    cumulativeSellBpsMoved = 0;
    emit BaselinesReset(lastBuyPriceRay, lastSellPriceRay);
  }

  /*//////////////////////////////////////////////////////////////
                              READS
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IOracle
  function buyRate() public view returns (uint256 rateRay) {
    if (paused()) revert Errors.OracleStale();
    // D-3: same-block-as-update reject (sandwich-protection).
    if (block.number == lastUpdateBlock && msg.sender != owner()) revert Errors.SameBlockUse();
    return lastBuyPriceRay;
  }

  /// @inheritdoc IOracle
  function sellRate() public view returns (uint256 rateRay) {
    if (paused()) revert Errors.OracleStale();
    // D-3: same-block-as-update reject (sandwich-protection).
    if (block.number == lastUpdateBlock && msg.sender != owner()) revert Errors.SameBlockUse();
    return lastSellPriceRay;
  }

  /// @inheritdoc IOracle
  function paused() public view returns (bool) {
    if (_deviationPaused) return true;
    if (block.timestamp > lastUpdateAt + MAX_AGE) return true;
    return false;
  }

  /*//////////////////////////////////////////////////////////////
                            INTERNAL
  //////////////////////////////////////////////////////////////*/

  /// @dev Absolute delta between two RAY-scaled prices, expressed in BPS of `against`.
  function _absDeltaBps(uint256 priceRay, uint256 against) private pure returns (uint256) {
    if (against == 0) return type(uint256).max;
    uint256 diff = priceRay > against ? priceRay - against : against - priceRay;
    return (diff * MathUtils.BPS_DIVISOR) / against;
  }
}
