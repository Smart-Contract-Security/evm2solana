// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Textile, Inc.
// This smart contract is part of the Textile Protocol (Settlement v3).
pragma solidity 0.8.30;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { MathUtils } from "../../../v2.1/libraries/math/MathUtils.sol";

/**
 * @title FeeLogic
 * @notice Pure math for the Settlement v3 fee curve and fill-time distribution.
 *         Single source of truth shared by SettlementPool and the reference-math
 *         tests in commit [03]. Mirrors the v2.1 layout (`libraries/logic/`).
 *
 * @dev Rev3 splits close-time math across both assets:
 *      - debt asset pays CP principal, CP yield, trader refund, and the
 *        CP-yield protocol fee;
 *      - collateral asset pays the filler, net of the filler-leg protocol fee.
 *
 *      Conservation invariants (asserted by Pool):
 *          fillerDebtIn = cpPrincipal + cpYieldNet + traderRefund + cpProtocolFeeDebt
 *          C = fillerCollateralOut + fillerProtocolFeeCollateral
 *
 *      Protocol fees round up, capped at the at-window per-leg maximum.
 *
 *      Reference impl mirror: any change to this library MUST be mirrored in
 *      `test/helpers/feeMath.ts` (commit [03]).
 */
library FeeLogic {
  /// @notice Protocol fee taken from each leg (closer + LP), capped at the in-window max.
  uint256 internal constant PROTOCOL_FEE_BPS = 1000; // 10%

  struct FillQuote {
    uint256 feeRay;
    uint256 fillerDebtIn;
    uint256 fillerCollateralOut;
    uint256 cpPrincipalDebt;
    uint256 cpYieldDebtNet;
    uint256 traderRefundDebt;
    uint256 cpProtocolFeeDebt;
    uint256 fillerProtocolFeeCollateral;
    uint256 lpPrincipalLoss;
  }

  /**
   * @dev Linear Dutch auction fee plus CP principal return.
   *      In window:   fee(t) = floor + (buffer - floor) * t / window; principal = D
   *      Past window: fee = buffer (capped); principal = D * (1 - buffer*(t-window)/window),
   *                   clamped at 0.
   */
  function feeAndPrincipal(
    uint256 D,
    uint256 elapsed,
    uint256 floorRay,
    uint256 bufferRay,
    uint256 window
  ) internal pure returns (uint256 feeRay, uint256 cpPrincipalDebt) {
    if (elapsed >= window) {
      feeRay = bufferRay;
      uint256 dt = elapsed - window;
      uint256 decayFraction = Math.mulDiv(bufferRay, dt, window);
      if (decayFraction >= MathUtils.RAY) {
        cpPrincipalDebt = 0;
      } else {
        uint256 factor = MathUtils.RAY - decayFraction;
        cpPrincipalDebt = Math.mulDiv(D, factor, MathUtils.RAY);
      }
    } else {
      feeRay = floorRay + Math.mulDiv(bufferRay - floorRay, elapsed, window);
      cpPrincipalDebt = D;
    }
  }

  /**
   * @dev Full rev3 fill quote.
   *      Debt side:
   *        in-window fillerDebtIn = D + D*fee/2 + D*(buffer-fee)
   *        past-window fillerDebtIn = D' + D*buffer/2
   *      Collateral side:
   *        filler receives C minus the protocol fee on the filler margin.
   */
  function quoteFill(
    uint256 C,
    uint256 D,
    uint256 elapsed,
    uint256 floorRay,
    uint256 bufferRay,
    uint256 window
  ) internal pure returns (FillQuote memory q) {
    (q.feeRay, q.cpPrincipalDebt) = feeAndPrincipal(D, elapsed, floorRay, bufferRay, window);

    uint256 cpYieldDebtGross = Math.mulDiv(D, q.feeRay, MathUtils.RAY * 2);
    q.cpProtocolFeeDebt = protocolFeeFromAmount(cpYieldDebtGross, Math.mulDiv(D, bufferRay, MathUtils.RAY * 2));
    q.cpYieldDebtNet = cpYieldDebtGross - q.cpProtocolFeeDebt;

    if (elapsed < window && q.feeRay < bufferRay) {
      q.traderRefundDebt = Math.mulDiv(D, bufferRay - q.feeRay, MathUtils.RAY);
    }

    q.fillerDebtIn = q.cpPrincipalDebt + cpYieldDebtGross + q.traderRefundDebt;
    q.lpPrincipalLoss = D - q.cpPrincipalDebt;

    uint256 fillerMarginCollateral = Math.mulDiv(C, q.feeRay, (MathUtils.RAY + bufferRay) * 2);
    uint256 fillerMarginCapCollateral = Math.mulDiv(C, bufferRay, (MathUtils.RAY + bufferRay) * 2);
    q.fillerProtocolFeeCollateral = protocolFeeFromAmount(fillerMarginCollateral, fillerMarginCapCollateral);
    q.fillerCollateralOut = C - q.fillerProtocolFeeCollateral;
  }

  /**
   * @dev Protocol fee = min(amount * PROTOCOL_FEE_BPS / 10000, capAmount * PROTOCOL_FEE_BPS / 10000).
   *      Round the live fee up in protocol's favor; keep the cap rounded down.
   */
  function protocolFeeFromAmount(uint256 amount, uint256 capAmount) internal pure returns (uint256 proto) {
    if (amount == 0 || capAmount == 0) return 0;
    uint256 cap = Math.mulDiv(capAmount, PROTOCOL_FEE_BPS, MathUtils.BPS_DIVISOR);
    uint256 raw = Math.mulDiv(amount, PROTOCOL_FEE_BPS, MathUtils.BPS_DIVISOR, Math.Rounding.Ceil);
    proto = raw < cap ? raw : cap;
  }
}
