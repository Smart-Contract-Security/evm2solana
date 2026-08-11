// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (utils/math/Math.sol)

/**
 * @dev Standard math utilities missing in the Solidity language.
 */
library Math {
    enum Rounding {
        Floor, // Toward negative infinity
        Ceil, // Toward positive infinity
        Trunc, // Toward zero
        Expand // Away from zero
    }

    /**
     * @dev Returns the addition of two unsigned integers, with an overflow flag.
     */
    function tryAdd(uint64 a, uint64 b) internal pure returns (bool, uint64) {
        unchecked {
            uint64 c = a + b;
            if (c < a) return (false, 0);
            return (true, c);
        }
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, with an overflow flag.
     */
    function trySub(uint64 a, uint64 b) internal pure returns (bool, uint64) {
        unchecked {
            if (b > a) return (false, 0);
            return (true, a - b);
        }
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, with an overflow flag.
     */
    function tryMul(uint64 a, uint64 b) internal pure returns (bool, uint64) {
        unchecked {
            if (a == 0) return (true, 0);
            uint64 c = a * b;
            if (c / a != b) return (false, 0);
            return (true, c);
        }
    }

    /**
     * @dev Returns the division of two unsigned integers, with a division by zero flag.
     */
    function tryDiv(uint64 a, uint64 b) internal pure returns (bool, uint64) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a / b);
        }
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers, with a division by zero flag.
     */
    function tryMod(uint64 a, uint64 b) internal pure returns (bool, uint64) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a % b);
        }
    }

    /**
     * @dev Returns the largest of two numbers.
     */
    function max(uint64 a, uint64 b) internal pure returns (uint64) {
        return a > b ? a : b;
    }

    /**
     * @dev Returns the smallest of two numbers.
     */
    function min(uint64 a, uint64 b) internal pure returns (uint64) {
        return a < b ? a : b;
    }

    /**
     * @dev Returns the average of two numbers. The result is rounded towards
     * zero.
     */
    function average(uint64 a, uint64 b) internal pure returns (uint64) {
        // (a + b) / 2 can overflow.
        return (a & b) + (a ^ b) / 2;
    }

    /**
     * @dev Returns the ceiling of the division of two numbers.
     *
     * This differs from standard division with `/` in that it rounds towards infinity instead
     * of rounding towards zero.
     */
    function ceilDiv(uint64 a, uint64 b) internal pure returns (uint64) {
        if (b == 0) {
            // Guarantee the same behavior as in a regular Solidity division.
            return a / b;
        }

        // (a + b - 1) / b can overflow on addition, so we distribute.
        return a == 0 ? 0 : (a - 1) / b + 1;
    }

    /**
     * @notice Calculates floor(x * y / denominator) with full precision. Throws if result overflows a uint64 or
     * denominator == 0.
     */
    function mulDiv(uint64 x, uint64 y, uint64 denominator) internal pure returns (uint64 result) {
        unchecked {
            uint64 prod0 = x * y;
            uint64 prod1;
            // No assembly available on Solana, use pure Solidity
            uint64 mm = mulmod(x, y, type(uint64).max);
            prod1 = mm - prod0;
            if (mm < prod0) {
                prod1 -= 1;
            }

            if (prod1 == 0) {
                return prod0 / denominator;
            }

            if (denominator <= prod1) {
                revert("MathOverflowedMulDiv");
            }

            uint64 remainder = mulmod(x, y, denominator);

            if (remainder > prod0) {
                prod1 -= 1;
            }
            prod0 -= remainder;

            uint64 twos = denominator & (0 - denominator);
            denominator /= twos;
            prod0 /= twos;
            twos = (0 - twos) / twos + 1;

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

    /**
     * @notice Calculates x * y / denominator with full precision, following the selected rounding direction.
     */
    function mulDiv(uint64 x, uint64 y, uint64 denominator, Rounding rounding) internal pure returns (uint64) {
        uint64 result = mulDiv(x, y, denominator);
        if (unsignedRoundsUp(rounding) && mulmod(x, y, denominator) > 0) {
            result += 1;
        }
        return result;
    }

    /**
     * @dev Returns the square root of a number. If the number is not a perfect square, the value is rounded
     * towards zero.
     *
     * Inspired by Henry S. Warren, Jr.'s "Hacker's Delight" (Chapter 11).
     */
    function sqrt(uint64 a) internal pure returns (uint64) {
        if (a == 0) {
            return 0;
        }

        uint64 result = 1 << (log2(a) >> 1);

        unchecked {
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            return min(result, a / result);
        }
    }

    /**
     * @notice Calculates sqrt(a), following the selected rounding direction.
     */
    function sqrt(uint64 a, Rounding rounding) internal pure returns (uint64) {
        unchecked {
            uint64 result = sqrt(a);
            return result + (unsignedRoundsUp(rounding) && result * result < a ? 1 : 0);
        }
    }

    /**
     * @dev Return the log in base 2 of a positive value rounded towards zero.
     * Returns 0 if given 0.
     */
    function log2(uint64 value) internal pure returns (uint64) {
        uint64 result = 0;
        unchecked {
            if (value >> 32 > 0) {
                value >>= 32;
                result += 32;
            }
            if (value >> 16 > 0) {
                value >>= 16;
                result += 16;
            }
            if (value >> 8 > 0) {
                value >>= 8;
                result += 8;
            }
            if (value >> 4 > 0) {
                value >>= 4;
                result += 4;
            }
            if (value >> 2 > 0) {
                value >>= 2;
                result += 2;
            }
            if (value >> 1 > 0) {
                result += 1;
            }
        }
        return result;
    }

    /**
     * @dev Return the log in base 2, following the selected rounding direction, of a positive value.
     * Returns 0 if given 0.
     */
    function log2(uint64 value, Rounding rounding) internal pure returns (uint64) {
        unchecked {
            uint64 result = log2(value);
            return result + (unsignedRoundsUp(rounding) && uint64(1) << result < value ? 1 : 0);
        }
    }

    /**
     * @dev Return the log in base 10 of a positive value rounded towards zero.
     * Returns 0 if given 0.
     */
    function log10(uint64 value) internal pure returns (uint64) {
        uint64 result = 0;
        unchecked {
            if (value >= 10 ** 18) {
                value /= 10 ** 18;
                result += 18;
            }
            if (value >= 10 ** 9) {
                value /= 10 ** 9;
                result += 9;
            }
            if (value >= 10 ** 6) {
                value /= 10 ** 6;
                result += 6;
            }
            if (value >= 10 ** 3) {
                value /= 10 ** 3;
                result += 3;
            }
            if (value >= 10 ** 2) {
                value /= 10 ** 2;
                result += 2;
            }
            if (value >= 10 ** 1) {
                result += 1;
            }
        }
        return result;
    }

    /**
     * @dev Return the log in base 10, following the selected rounding direction, of a positive value.
     * Returns 0 if given 0.
     */
    function log10(uint64 value, Rounding rounding) internal pure returns (uint64) {
        unchecked {
            uint64 result = log10(value);
            return result + (unsignedRoundsUp(rounding) && 10 ** result < value ? 1 : 0);
        }
    }

    /**
     * @dev Return the log in base 256 of a positive value rounded towards zero.
     * Returns 0 if given 0.
     *
     * Adding one to the result gives the number of pairs of hex symbols needed to represent `value` as a hex string.
     */
    function log256(uint64 value) internal pure returns (uint64) {
        uint64 result = 0;
        unchecked {
            if (value >> 32 > 0) {
                value >>= 32;
                result += 4;
            }
            if (value >> 16 > 0) {
                value >>= 16;
                result += 2;
            }
            if (value >> 8 > 0) {
                result += 1;
            }
        }
        return result;
    }

    /**
     * @dev Return the log in base 256, following the selected rounding direction, of a positive value.
     * Returns 0 if given 0.
     */
    function log256(uint64 value, Rounding rounding) internal pure returns (uint64) {
        unchecked {
            uint64 result = log256(value);
            return result + (unsignedRoundsUp(rounding) && uint64(1) << (result << 3) < value ? 1 : 0);
        }
    }

    /**
     * @dev Returns whether a provided rounding mode is considered rounding up for unsigned integers.
     */
    function unsignedRoundsUp(Rounding rounding) internal pure returns (bool) {
        return uint8(rounding) % 2 == 1;
    }
}