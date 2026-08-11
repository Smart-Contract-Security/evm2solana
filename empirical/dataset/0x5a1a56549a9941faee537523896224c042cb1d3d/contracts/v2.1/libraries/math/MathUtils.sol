// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

library MathUtils {
  uint256 internal constant RAY = 1e27;
  uint256 internal constant SECONDS_PER_YEAR = 365 days;
  uint256 internal constant BPS_DIVISOR = 10000;

  // Binomial approximation for per-second compounding up to 4th order
  // (1 + x)^n ≈ 1 + n x + n(n-1)/2 x^2 + n(n-1)(n-2)/6 x^3 + n(n-1)(n-2)(n-3)/24 x^4
  // where x = r_sec (RAY), n = dtSeconds
  function compoundPerSecondRayBinomial(
    uint256 currentIndexRay,
    uint256 annualRateRay,
    uint256 dtSeconds
  ) internal pure returns (uint256) {
    if (dtSeconds == 0 || annualRateRay == 0) return currentIndexRay;

    // Early exit if rate too small to matter after division
    if (annualRateRay / SECONDS_PER_YEAR == 0) return currentIndexRay;

    // factorRay accumulates (1 + x)^n terms, starting at 1.0 in RAY
    uint256 factorRay = RAY;

    // First order: n*x = dtSeconds * (annualRateRay / SECONDS_PER_YEAR)
    factorRay += (annualRateRay * dtSeconds) / SECONDS_PER_YEAR;

    if (dtSeconds >= 2) {
      // Cache binomial coefficients to avoid recomputation
      uint256 nMinus1 = dtSeconds * (dtSeconds - 1);

      // Second order: n(n-1)/2 * x^2
      // x^2 = (annualRateRay / SECONDS_PER_YEAR)^2 = annualRateRay^2 / SECONDS_PER_YEAR^2 / RAY
      uint256 x2 = rayMul(annualRateRay, annualRateRay) / (SECONDS_PER_YEAR * SECONDS_PER_YEAR);
      factorRay += (x2 * nMinus1) / 2;

      if (dtSeconds >= 3) {
        uint256 nMinus2 = nMinus1 * (dtSeconds - 2);

        // Third order: n(n-1)(n-2)/6 * x^3
        // x^3 = x^2 * (annualRateRay / SECONDS_PER_YEAR)
        uint256 x3 = rayMul(x2, annualRateRay) / SECONDS_PER_YEAR;
        factorRay += (x3 * nMinus2) / 6;

        if (dtSeconds >= 4) {
          uint256 nMinus3 = nMinus2 * (dtSeconds - 3);

          // Fourth order: n(n-1)(n-2)(n-3)/24 * x^4
          // x^4 = x^3 * (annualRateRay / SECONDS_PER_YEAR)
          uint256 x4 = rayMul(x3, annualRateRay) / SECONDS_PER_YEAR;
          factorRay += (x4 * nMinus3) / 24;
        }
      }
    }

    return rayMul(currentIndexRay, factorRay);
  }

  function rayMul(uint256 aRay, uint256 bRay) internal pure returns (uint256) {
    return Math.mulDiv(aRay, bRay, RAY);
  }

  function rayPow(uint256 baseRay, uint256 exp) internal pure returns (uint256 resultRay) {
    resultRay = RAY;
    uint256 b = baseRay;
    uint256 e = exp;
    while (e > 0) {
      if (e & 1 == 1) {
        resultRay = rayMul(resultRay, b);
      }
      e >>= 1;
      if (e > 0) {
        b = rayMul(b, b);
      }
    }
    return resultRay;
  }

  /*//////////////////////////////////////////////////////////////
                        FEE CALCULATION FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Calculate fee from amount that already includes fees (OpenZeppelin pattern)
   * @dev Used for deposit/redeem where user provides total amount including fees
   * Formula: fee = assets * feeBps / (feeBps + 10000)
   * @param assets Total assets including fees
   * @param feeBps Fee in basis points
   * @return fee The calculated fee amount
   */
  function feeOnTotal(uint256 assets, uint256 feeBps) internal pure returns (uint256 fee) {
    return Math.mulDiv(assets, feeBps, feeBps + BPS_DIVISOR, Math.Rounding.Ceil);
  }

  /**
   * @notice Calculate fee to add on top of raw amount (OpenZeppelin pattern)
   * @dev Used for mint/withdraw where user specifies exact shares/assets
   * Formula: fee = assets * feeBps / 10000
   * @param assets Raw assets before fees
   * @param feeBps Fee in basis points
   * @return fee The calculated fee amount
   */
  function feeOnRaw(uint256 assets, uint256 feeBps) internal pure returns (uint256 fee) {
    return Math.mulDiv(assets, feeBps, BPS_DIVISOR, Math.Rounding.Ceil);
  }
}
