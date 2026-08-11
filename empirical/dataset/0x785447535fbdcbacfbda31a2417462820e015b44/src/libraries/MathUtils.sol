// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title MathUtils library
 * @author Shred (adapted from Aave V3)
 * @notice Provides functions to perform compounded interest calculations
 * @dev Based on Aave V3's MathUtils.sol
 * @dev See: github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/math/MathUtils.sol
 */
library MathUtils {
    /// @dev RAY precision (27 decimals) for fixed-point math
    uint256 internal constant RAY = 1e27;

    /// @dev Ignoring leap years
    uint256 internal constant SECONDS_PER_YEAR = 365 days;

    /**
     * @dev Function to calculate the interest using a compounded interest rate formula
     * To avoid expensive exponentiation, the calculation is performed using a binomial approximation:
     *
     *  (1+x)^n = 1+n*x+[n/2*(n-1)]*x^2+[n/6*(n-1)*(n-2)*x^3...
     *
     * The approximation slightly underpays liquidity providers and undercharges borrowers,
     * with the advantage of great gas cost reductions. See Aave whitepaper for error margins.
     *
     * @param rate The interest rate, in ray (annual rate)
     * @param lastUpdateTimestamp The timestamp of the last update of the interest
     * @param currentTimestamp The current timestamp
     * @return The interest rate compounded during the timeDelta, in ray
     */
    function calculateCompoundedInterest(
        uint256 rate,
        uint256 lastUpdateTimestamp,
        uint256 currentTimestamp
    ) internal pure returns (uint256) {
        uint256 exp = currentTimestamp - lastUpdateTimestamp;

        if (exp == 0) {
            return RAY;
        }

        uint256 expMinusOne;
        uint256 expMinusTwo;
        uint256 basePowerTwo;
        uint256 basePowerThree;

        unchecked {
            expMinusOne = exp - 1;
            expMinusTwo = exp > 2 ? exp - 2 : 0;

            basePowerTwo = rayMul(rate, rate) / (SECONDS_PER_YEAR * SECONDS_PER_YEAR);
            basePowerThree = rayMul(basePowerTwo, rate) / SECONDS_PER_YEAR;
        }

        uint256 secondTerm = exp * expMinusOne * basePowerTwo;
        unchecked {
            secondTerm /= 2;
        }

        uint256 thirdTerm = exp * expMinusOne * expMinusTwo * basePowerThree;
        unchecked {
            thirdTerm /= 6;
        }

        return RAY + (rate * exp) / SECONDS_PER_YEAR + secondTerm + thirdTerm;
    }

    /**
     * @dev Calculates the compounded interest between the timestamp of the last update and the current block timestamp
     * @param rate The interest rate (in ray, annual rate)
     * @param lastUpdateTimestamp The timestamp from which the interest accumulation needs to be calculated
     * @return The interest rate compounded between lastUpdateTimestamp and current block timestamp, in ray
     */
    function calculateCompoundedInterest(uint256 rate, uint256 lastUpdateTimestamp) internal view returns (uint256) {
        return calculateCompoundedInterest(rate, lastUpdateTimestamp, block.timestamp);
    }

    /**
     * @dev Multiplies two ray values, rounding half up to the nearest ray
     * @param a First ray value
     * @param b Second ray value
     * @return The result of a * b, in ray
     */
    function rayMul(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a * b + RAY / 2) / RAY;
    }
}
