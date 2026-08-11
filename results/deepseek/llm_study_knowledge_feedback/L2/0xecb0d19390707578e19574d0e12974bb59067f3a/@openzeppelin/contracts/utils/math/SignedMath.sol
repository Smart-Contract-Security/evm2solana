// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.8.0) (utils/math/SignedMath.sol)

/**
 * @dev Standard signed math utilities missing in the Solidity language.
 */
library SignedMath {
    /**
     * @dev Returns the largest of two signed numbers.
     */
    function max(int64 a, int64 b) internal pure returns (int64) {
        return a > b ? a : b;
    }

    /**
     * @dev Returns the smallest of two signed numbers.
     */
    function min(int64 a, int64 b) internal pure returns (int64) {
        return a < b ? a : b;
    }

    /**
     * @dev Returns the average of two signed numbers without overflow.
     * The result is rounded towards zero.
     */
    function average(int64 a, int64 b) internal pure returns (int64) {
        // Formula from the book "Hacker's Delight"
        int64 x = (a & b) + ((a ^ b) >> 1);
        return x + (int64(uint64(x) >> 63) & (a ^ b));
    }

    /**
     * @dev Returns the absolute unsigned value of a signed value.
     */
    function abs(int64 n) internal pure returns (uint64) {
        unchecked {
            // must be unchecked in order to support `n = type(int64).min`
            return uint64(n >= 0 ? n : -n);
        }
    }
}