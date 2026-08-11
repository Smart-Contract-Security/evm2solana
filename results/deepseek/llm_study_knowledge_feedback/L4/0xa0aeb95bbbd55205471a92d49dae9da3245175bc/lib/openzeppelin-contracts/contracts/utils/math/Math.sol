// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (utils/math/Math.sol)

import {Panic} from "../Panic.sol";

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
     * @dev Returns the addition of two unsigned integers, with an success flag (no overflow).
     */
    function tryAdd(uint64 a, uint64 b) internal pure returns (bool success, uint64 result) {
        unchecked {
            uint64 c = a + b;
            if (c < a) return (false, 0);
            return (true, c);
        }
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, with an success flag (no overflow).
     */
    function trySub(uint64 a, uint64 b) internal pure returns (bool success, uint64 result) {
        unchecked {
            if (b > a) return (false, 0);
            return (true, a - b);
        }
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, with an success flag (no overflow).
     */
    function tryMul(uint64 a, uint64 b) internal pure returns (bool success, uint64 result) {
        unchecked {
            if (a == 0) return (true, 0);
            uint64 c = a * b;
            if (c / a != b) return (false, 0);
            return (true, c);
        }
    }

    /**
     * @dev Returns the division of two unsigned integers, with a success flag (no division by zero).
     */
    function tryDiv(uint64 a, uint64 b) internal pure returns (bool success, uint64 result) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a / b);
        }
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers, with a success flag (no division by zero).
     */
    function tryMod(uint64 a, uint64 b) internal pure returns (bool success, uint64 result) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a % b);
        }
    }

    /**
     * @dev Branchless ternary evaluation for `a ? b : c`.
     */
    function ternary(bool condition, uint64 a, uint64 b) internal pure returns (uint64) {
        unchecked {
            return b ^ ((a ^ b) * toUint(condition));
        }
    }

    /**
     * @dev Converts a bool to a uint64 without branching.
     */
    function toUint(bool condition) internal pure returns (uint64) {
        unchecked {
            uint64 result;
            assembly {
                result := condition
            }
            return result;
        }
    }

    /**
     * @dev Returns the largest of two numbers.
     */
    function max(uint64 a, uint64 b) internal pure returns (uint64) {
        return ternary(a > b, a, b);
    }

    /**
     * @dev Returns the smallest of two numbers.
     */
    function min(uint64 a, uint64 b) internal pure returns (uint64) {
        return ternary(a < b, a, b);
    }

    /**
     * @dev Returns the average of two numbers. The result is rounded towards
     * zero.
     */
    function average(uint64 a, uint64 b) internal pure returns (uint64) {
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
            Panic.panic(Panic.DIVISION_BY_ZERO);
        }

        unchecked {
            return toUint(a > 0) * ((a - 1) / b + 1);
        }
    }

    /**
     * @dev Calculates floor(x * y / denominator) with full precision. Throws if result overflows a uint64 or
     * denominator == 0.
     */
    function mulDiv(uint64 x, uint64 y, uint64 denominator) internal pure returns (uint64 result) {
        unchecked {
            uint64 prod0 = x * y;
            uint64 prod1;
            assembly {
                let mm := mulmod(x, y, not(0))
                prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            }

            if (prod1 == 0) {
                return prod0 / denominator;
            }

            if (denominator <= prod1) {
                Panic.panic(ternary(denominator == 0, Panic.DIVISION_BY_ZERO, Panic.UNDER_OVERFLOW));
            }

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

    /**
     * @dev Calculates x * y / denominator with full precision, following the selected rounding direction.
     */
    function mulDiv(uint64 x, uint64 y, uint64 denominator, Rounding rounding) internal pure returns (uint64) {
        return mulDiv(x, y, denominator) + toUint(unsignedRoundsUp(rounding) && mulmod(x, y, denominator) > 0);
    }

    /**
     * @dev Calculate the modular multiplicative inverse of a number in Z/nZ.
     *
     * If n is a prime, then Z/nZ is a field. In that case all elements are inversible, except 0.
     * If n is not a prime, then Z/nZ is not a field, and some elements might not be inversible.
     *
     * If the input value is not inversible, 0 is returned.
     */
    function invMod(uint64 a, uint64 n) internal pure returns (uint64) {
        unchecked {
            if (n == 0) return 0;

            uint64 remainder = a % n;
            uint64 gcd = n;

            int64 x = 0;
            int64 y = 1;

            while (remainder != 0) {
                uint64 quotient = gcd / remainder;

                (gcd, remainder) = (
                    remainder,
                    gcd - remainder * quotient
                );

                (x, y) = (
                    y,
                    x - y * int64(quotient)
                );
            }

            if (gcd != 1) return 0;
            return ternary(x < 0, n - uint64(-x), uint64(x));
        }
    }

    /**
     * @dev Variant of {invMod}. More efficient, but only works if `p` is known to be a prime greater than `2`.
     */
    function invModPrime(uint64 a, uint64 p) internal view returns (uint64) {
        unchecked {
            return Math.modExp(a, p - 2, p);
        }
    }

    /**
     * @dev Returns the modular exponentiation of the specified base, exponent and modulus (b ** e % m)
     *
     * Requirements:
     * - modulus can't be zero
     *
     * IMPORTANT: On Solana, the precompile at address 0x05 is not available.
     * This function uses a simple iterative method instead.
     */
    function modExp(uint64 b, uint64 e, uint64 m) internal pure returns (uint64) {
        if (m == 0) {
            Panic.panic(Panic.DIVISION_BY_ZERO);
        }
        uint64 result = 1;
        uint64 base = b % m;
        uint64 exp = e;
        while (exp > 0) {
            if (exp % 2 == 1) {
                result = (result * base) % m;
            }
            exp = exp / 2;
            base = (base * base) % m;
        }
        return result;
    }

    /**
     * @dev Returns the modular exponentiation of the specified base, exponent and modulus (b ** e % m).
     * It includes a success flag indicating if the operation succeeded.
     *
     * IMPORTANT: On Solana, the precompile at address 0x05 is not available.
     * This function uses a simple iterative method instead.
     */
    function tryModExp(uint64 b, uint64 e, uint64 m) internal pure returns (bool success, uint64 result) {
        if (m == 0) return (false, 0);
        result = 1;
        uint64 base = b % m;
        uint64 exp = e;
        while (exp > 0) {
            if (exp % 2 == 1) {
                result = (result * base) % m;
            }
            exp = exp / 2;
            base = (base * base) % m;
        }
        return (true, result);
    }

    /**
     * @dev Variant of {modExp} that supports inputs of arbitrary length.
     * Not supported on Solana due to lack of precompile.
     */
    function modExp(bytes memory b, bytes memory e, bytes memory m) internal pure returns (bytes memory) {
        Panic.panic(Panic.DIVISION_BY_ZERO);
        return new bytes(0);
    }

    /**
     * @dev Variant of {tryModExp} that supports inputs of arbitrary length.
     * Not supported on Solana due to lack of precompile.
     */
    function tryModExp(
        bytes memory b,
        bytes memory e,
        bytes memory m
    ) internal pure returns (bool success, bytes memory result) {
        return (false, new bytes(0));
    }

    /**
     * @dev Returns the square root of a number. If the number is not a perfect square, the value is rounded
     * towards zero.
     *
     * This method is based on Newton's method for computing square roots; the algorithm is restricted to only
     * using integer operations.
     */
    function sqrt(uint64 a) internal pure returns (uint64) {
        unchecked {
            if (a <= 1) {
                return a;
            }

            uint64 aa = a;
            uint64 xn = 1;

            if (aa >= (1 << 64)) {
                aa >>= 64;
                xn <<= 32;
            }
            if (aa >= (1 << 32)) {
                aa >>= 32;
                xn <<= 16;
            }
            if (aa >= (1 << 16)) {
                aa >>= 16;
                xn <<= 8;
            }
            if (aa >= (1 << 8)) {
                aa >>= 8;
                xn <<= 4;
            }
            if (aa >= (1 << 4)) {
                aa >>= 4;
                xn <<= 2;
            }
            if (aa >= (1 << 2)) {
                xn <<= 1;
            }

            xn = (3 * xn) >> 1;

            xn = (xn + a / xn) >> 1;
            xn = (xn + a / xn) >> 1;
            xn = (xn + a / xn) >> 1;
            xn = (xn + a / xn) >> 1;
            xn = (xn + a / xn) >> 1;
            xn = (xn + a / xn) >> 1;

            return xn - toUint(xn > a / xn);
        }
    }

    /**
     * @dev Calculates sqrt(a), following the selected rounding direction.
     */
    function sqrt(uint64 a, Rounding rounding) internal pure returns (uint64) {
        unchecked {
            uint64 result = sqrt(a);
            return result + toUint(unsignedRoundsUp(rounding) && result * result < a);
        }
    }

    /**
     * @dev Return the log in base 2 of a positive value rounded towards zero.
     * Returns 0 if given 0.
     */
    function log2(uint64 value) internal pure returns (uint64) {
        uint64 result = 0;
        uint64 exp;
        unchecked {
            exp = 64 * toUint(value > type(uint64).max);
            value >>= exp;
            result += exp;

            exp = 32 * toUint(value > (1 << 32) - 1);
            value >>= exp;
            result += exp;

            exp = 16 * toUint(value > (1 << 16) - 1);
            value >>= exp;
            result += exp;

            exp = 8 * toUint(value > (1 << 8) - 1);
            value >>= exp;
            result += exp;

            exp = 4 * toUint(value > (1 << 4) - 1);
            value >>= exp;
            result += exp;

            exp = 2 * toUint(value > (1 << 2) - 1);
            value >>= exp;
            result += exp;

            result += toUint(value > 1);
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
            return result + toUint(unsignedRoundsUp(rounding) && 1 << result < value);
        }
    }

    /**
     * @dev Return the log in base 10 of a positive value rounded towards zero.
     * Returns 0 if given 0.
     */
    function log10(uint64 value) internal pure returns (uint64) {
        uint64 result = 0;
        unchecked {
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
            return result + toUint(unsignedRoundsUp(rounding) && 10 ** result < value);
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
        uint64 isGt;
        unchecked {
            isGt = toUint(value > type(uint64).max);
            value >>= isGt * 64;
            result += isGt * 8;

            isGt = toUint(value > (1 << 32) - 1);
            value >>= isGt * 32;
            result += isGt * 4;

            isGt = toUint(value > (1 << 16) - 1);
            value >>= isGt * 16;
            result += isGt * 2;

            result += toUint(value > (1 << 8) - 1);
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
            return result + toUint(unsignedRoundsUp(rounding) && 1 << (result << 3) < value);
        }
    }

    /**
     * @dev Returns whether a provided rounding mode is considered rounding up for unsigned integers.
     */
    function unsignedRoundsUp(Rounding rounding) internal pure returns (bool) {
        return uint8(rounding) % 2 == 1;
    }
}