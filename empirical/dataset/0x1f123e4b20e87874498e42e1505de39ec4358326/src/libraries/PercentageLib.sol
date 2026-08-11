// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.30;

import {SECONDS_IN_YEAR} from "../Constants.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title PercentageLib
/// @notice Utilities for percentage calculations using basis points (bps).
library PercentageLib {
    using Math for uint256;

    /// @dev Basis points denominator representing 100% (10,000 bps = 100%).
    uint256 internal constant BPS_DENOMINATOR = 10_000;

    /// @dev Calculate a percentage of a value using basis points.
    function bps(uint256 value, uint16 rateBps) internal pure returns (uint256) {
        return value.mulDiv(rateBps, BPS_DENOMINATOR, Math.Rounding.Floor);
    }

    /// @dev Calculate annual pro-rata percentage accrual over a specified duration.
    function annualBpsProRata(uint256 value, uint16 rateBps, uint64 duration) internal pure returns (uint256) {
        uint256 denom = BPS_DENOMINATOR * SECONDS_IN_YEAR;
        uint256 numerator = uint256(rateBps) * duration;

        return value.mulDiv(numerator, denom, Math.Rounding.Floor);
    }

    /// @dev Calculate annual pro-rata percentage accrual over a specified duration, carrying forward a remainder.
    ///      The remainder is stored in `(10_000 * SECONDS_IN_YEAR)` denominator units and can be fed back in on
    ///      subsequent calls to prevent rounding-to-zero when streaming frequently.
    function annualBpsProRata(uint256 value, uint16 rateBps, uint64 duration, uint64 remainder)
        internal
        pure
        returns (uint256 amount, uint64 newRemainder)
    {
        uint256 denom = BPS_DENOMINATOR * SECONDS_IN_YEAR;
        uint256 numerator = uint256(rateBps) * duration;

        // Remainder is expected to be produced by this function and therefore bounded to the denominator.
        assert(uint256(remainder) < denom);

        amount = value.mulDiv(numerator, denom, Math.Rounding.Floor);

        uint256 sumRemainder = mulmod(value, numerator, denom) + remainder;
        if (sumRemainder >= denom) {
            amount += 1;
            sumRemainder -= denom;
        }

        newRemainder = uint64(sumRemainder);
    }
}
