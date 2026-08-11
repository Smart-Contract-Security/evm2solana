// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.0) (utils/math/Math.sol)

/**
 * @dev Standard math utilities missing in the Solidity language.
 */
library Math {
    enum Rounding {
        Down, // Toward negative infinity
        Up, // Toward infinity
        Zero // Toward zero
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
     * This differs from standard division with `/` in that it rounds up instead
     * of rounding down.
     */
    function ceilDiv(uint64 a, uint64 b) internal pure returns (uint64) {
        // (a + b - 1) / b can overflow on addition, so we distribute.
        return a == 0 ? 0 : (a - 1) / b + 1;
    }

    /**
     * @notice Calculates floor(x * y / denominator) with full precision. Throws if result overflows a uint64 or denominator == 0
     * @dev Original credit to Remco Bloemen under MIT license (https://xn--2-umb.com/21/muldiv)
     * with further edits by Uniswap Labs also under MIT license.
     */
    function mulDiv(uint64 x, uint64 y, uint64 denominator) internal pure returns (uint64 result) {
        // For 64-bit, we can use a simpler approach since overflow is less likely
        // but we still need to handle it carefully
        if (denominator == 0) {
            revert("Math: division by zero");
        }
        
        // Use 128-bit intermediate to avoid overflow
        uint128 prod = uint128(x) * uint128(y);
        if (prod / uint128(denominator) > type(uint64).max) {
            revert("Math: mulDiv overflow");
        }
        
        return uint64(prod / uint128(denominator));
    }

    /**
     * @notice Calculates x * y / denominator with full precision, following the selected rounding direction.
     */
    function mulDiv(uint64 x, uint64 y, uint64 denominator, Rounding rounding) internal pure returns (uint64) {
        uint64 result = mulDiv(x, y, denominator);
        if (rounding == Rounding.Up && (uint128(x) * uint128(y) % uint128(denominator)) > 0) {
            result += 1;
        }
        return result;
    }

    /**
     * @dev Returns the square root of a number. If the number is not a perfect square, the value is rounded down.
     *
     * Inspired by Henry S. Warren, Jr.'s "Hacker's Delight" (Chapter 11).
     */
    function sqrt(uint64 a) internal pure returns (uint64) {
        if (a == 0) {
            return 0;
        }

        // For our first guess, we get the biggest power of 2 which is smaller than the square root of the target.
        uint64 result = uint64(1 << (log2(a) >> 1));

        // Newton's method converges quadratically
        result = (result + a / result) >> 1;
        result = (result + a / result) >> 1;
        result = (result + a / result) >> 1;
        result = (result + a / result) >> 1;
        result = (result + a / result) >> 1;
        result = (result + a / result) >> 1;
        result = (result + a / result) >> 1;
        return min(result, a / result);
    }

    /**
     * @notice Calculates sqrt(a), following the selected rounding direction.
     */
    function sqrt(uint64 a, Rounding rounding) internal pure returns (uint64) {
        uint64 result = sqrt(a);
        return result + (rounding == Rounding.Up && result * result < a ? 1 : 0);
    }

    /**
     * @dev Return the log in base 2, rounded down, of a positive value.
     * Returns 0 if given 0.
     */
    function log2(uint64 value) internal pure returns (uint64) {
        uint64 result = 0;
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
        return result;
    }

    /**
     * @dev Return the log in base 2, following the selected rounding direction, of a positive value.
     * Returns 0 if given 0.
     */
    function log2(uint64 value, Rounding rounding) internal pure returns (uint64) {
        uint64 result = log2(value);
        return result + (rounding == Rounding.Up && uint64(1) << result < value ? 1 : 0);
    }

    /**
     * @dev Return the log in base 10, rounded down, of a positive value.
     * Returns 0 if given 0.
     */
    function log10(uint64 value) internal pure returns (uint64) {
        uint64 result = 0;
        if (value >= 10000000000000000000) {
            value /= 10000000000000000000;
            result += 19;
        }
        if (value >= 10000000000000000) {
            value /= 10000000000000000;
            result += 16;
        }
        if (value >= 100000000) {
            value /= 100000000;
            result += 8;
        }
        if (value >= 10000) {
            value /= 10000;
            result += 4;
        }
        if (value >= 100) {
            value /= 100;
            result += 2;
        }
        if (value >= 10) {
            result += 1;
        }
        return result;
    }

    /**
     * @dev Return the log in base 10, following the selected rounding direction, of a positive value.
     * Returns 0 if given 0.
     */
    function log10(uint64 value, Rounding rounding) internal pure returns (uint64) {
        uint64 result = log10(value);
        return result + (rounding == Rounding.Up && 10 ** result < value ? 1 : 0);
    }

    /**
     * @dev Return the log in base 256, rounded down, of a positive value.
     * Returns 0 if given 0.
     *
     * Adding one to the result gives the number of pairs of hex symbols needed to represent `value` as a hex string.
     */
    function log256(uint64 value) internal pure returns (uint64) {
        uint64 result = 0;
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
        return result;
    }

    /**
     * @dev Return the log in base 256, following the selected rounding direction, of a positive value.
     * Returns 0 if given 0.
     */
    function log256(uint64 value, Rounding rounding) internal pure returns (uint64) {
        uint64 result = log256(value);
        return result + (rounding == Rounding.Up && uint64(1) << (result << 3) < value ? 1 : 0);
    }
}