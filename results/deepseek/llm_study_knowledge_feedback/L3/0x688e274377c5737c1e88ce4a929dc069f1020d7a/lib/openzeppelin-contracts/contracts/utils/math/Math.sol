// SPDX-License-Identifier: MIT

/// @title Math
/// @notice OpenZeppelin Math minimal compatible library, currently only full-precision mulDiv is needed.
library Math {
    /// @notice Compute floor(x * y / denominator), supporting 512-bit intermediate product to avoid x * y overflow.
    function mulDiv(uint64 x, uint64 y, uint64 denominator) internal pure returns (uint64 result) {
        unchecked {
            uint64 prod0;
            uint64 prod1;
            // Use inline assembly for 128-bit multiplication
            assembly {
                let mm := mulmod(x, y, not(0))
                prod0 := mul(x, y)
                prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            }

            if (prod1 == 0) {
                require(denominator > 0, "Math: div0");
                return prod0 / denominator;
            }

            require(denominator > prod1, "Math: overflow");

            uint64 remainder;
            assembly {
                remainder := mulmod(x, y, denominator)
                prod1 := sub(prod1, gt(remainder, prod0))
                prod0 := sub(prod0, remainder)
            }

            uint64 twos = denominator & (0 - denominator);
            assembly {
                denominator := div(denominator, twos)
                prod0 := div(prod0, twos)
                twos := add(div(sub(0, twos), twos), 1)
            }
            prod0 |= prod1 * twos;

            uint64 inverse = (3 * denominator) ^ 2;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;

            result = prod0 * inverse;
            return result;
        }
    }
}