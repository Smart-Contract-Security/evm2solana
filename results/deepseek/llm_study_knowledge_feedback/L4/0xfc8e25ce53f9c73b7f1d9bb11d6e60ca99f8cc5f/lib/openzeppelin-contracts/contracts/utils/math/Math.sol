// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (utils/math/Math.sol)

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

    // Constants for panic codes
    uint64 constant DIVISION_BY_ZERO = 0x12;
    uint64 constant UNDER_OVERFLOW = 0x11;

    /**
     * @dev Helper to convert bool to uint64 (replaces SafeCast.toUint(bool)).
     */
    function toUint(bool condition) private pure returns (uint64) {
        return condition ? 1 : 0;
    }

    /**
     * @dev Helper to panic with a given code.
     */
    function panic(uint64 code) private pure {
        revert();
    }

    /**
     * @dev Return the 512-bit addition of two uint64.
     *
     * The result is stored in two 64 variables such that sum = high * 2⁶⁴ + low.
     */
    function add512(uint64 a, uint64 b) internal pure returns (uint64 high, uint64 low) {
        low = a + b;
        high = ternary(low < a, 1, 0);
    }

    /**
     * @dev Return the 512-bit multiplication of two uint64.
     *
     * The result is stored in two 64 variables such that product = high * 2⁶⁴ + low.
     */
    function mul512(uint64 a, uint64 b) internal pure returns (uint64 high, uint64 low) {
        // 512-bit multiply [high low] = x * y. Compute the product mod 2⁶⁴ and mod 2⁶⁴ - 1, then use
        // the Chinese Remainder Theorem to reconstruct the 512 bit result. The result is stored in two 64
        // variables such that product = high * 2⁶⁴ + low.
        uint64 mm = mulmod(a, b, type(uint64).max);
        low = a * b;
        high = mm - low - ternary(mm < low, 1, 0);
    }

    /**
     * @dev Returns the addition of two unsigned integers, with a success flag (no overflow).
     */
    function tryAdd(uint64 a, uint64 b) internal pure returns (bool success, uint64 result) {
        unchecked {
            uint64 c = a + b;
            success = c >= a;
            result = c * toUint(success);
        }
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, with a success flag (no overflow).
     */
    function trySub(uint64 a, uint64 b) internal pure returns (bool success, uint64 result) {
        unchecked {
            uint64 c = a - b;
            success = c <= a;
            result = c * toUint(success);
        }
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, with a success flag (no overflow).
     */
    function tryMul(uint64 a, uint64 b) internal pure returns (bool success, uint64 result) {
        unchecked {
            uint64 c = a * b;
            // Only true when the multiplication doesn't overflow
            // (c / a == b) || (a == 0)
            success = (a == 0) || (c / a == b);
            // equivalent to: success ? c : 0
            result = c * toUint(success);
        }
    }

    /**
     * @dev Returns the division of two unsigned integers, with a success flag (no division by zero).
     */
    function tryDiv(uint64 a, uint64 b) internal pure returns (bool success, uint64 result) {
        unchecked {
            success = b > 0;
            // The `DIV` opcode returns zero when the denominator is 0.
            result = a / b;
        }
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers, with a success flag (no division by zero).
     */
    function tryMod(uint64 a, uint64 b) internal pure returns (bool success, uint64 result) {
        unchecked {
            success = b > 0;
            // The `MOD` opcode returns zero when the denominator is 0.
            result = a % b;
        }
    }

    /**
     * @dev Unsigned saturating addition, bounds to `2⁶⁴ - 1` instead of overflowing.
     */
    function saturatingAdd(uint64 a, uint64 b) internal pure returns (uint64) {
        (bool success, uint64 result) = tryAdd(a, b);
        return ternary(success, result, type(uint64).max);
    }

    /**
     * @dev Unsigned saturating subtraction, bounds to zero instead of overflowing.
     */
    function saturatingSub(uint64 a, uint64 b) internal pure returns (uint64) {
        (, uint64 result) = trySub(a, b);
        return result;
    }

    /**
     * @dev Unsigned saturating multiplication, bounds to `2⁶⁴ - 1` instead of overflowing.
     */
    function saturatingMul(uint64 a, uint64 b) internal pure returns (uint64) {
        (bool success, uint64 result) = tryMul(a, b);
        return ternary(success, result, type(uint64).max);
    }

    /**
     * @dev Branchless ternary evaluation for `a ? b : c`. Gas costs are constant.
     *
     * IMPORTANT: This function may reduce bytecode size and consume less gas when used standalone.
     * However, the compiler may optimize Solidity ternary operations (i.e. `a ? b : c`) to only compute
     * one branch when needed, making this function more expensive.
     */
    function ternary(bool condition, uint64 a, uint64 b) internal pure returns (uint64) {
        unchecked {
            // branchless ternary works because:
            // b ^ (a ^ b) == a
            // b ^ 0 == b
            return b ^ ((a ^ b) * toUint(condition));
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
            panic(DIVISION_BY_ZERO);
        }

        // The following calculation ensures accurate ceiling division without overflow.
        // Since a is non-zero, (a - 1) / b will not overflow.
        // The largest possible result occurs when (a - 1) / b is type(uint64).max,
        // but the largest value we can obtain is type(uint64).max - 1, which happens
        // when a = type(uint64).max and b = 1.
        unchecked {
            return toUint(a > 0) * ((a - 1) / b + 1);
        }
    }

    /**
     * @dev Calculates floor(x * y / denominator) with full precision. Throws if result overflows a uint64 or
     * denominator == 0.
     *
     * Original credit to Remco Bloemen under MIT license (https://xn--2-umb.com/21/muldiv) with further edits by
     * Uniswap Labs also under MIT license.
     */
    function mulDiv(uint64 x, uint64 y, uint64 denominator) internal pure returns (uint64 result) {
        unchecked {
            (uint64 high, uint64 low) = mul512(x, y);

            // Handle non-overflow cases, 64 by 64 division.
            if (high == 0) {
                // Solidity will revert if denominator == 0, unlike the div opcode on its own.
                // The surrounding unchecked block does not change this fact.
                // See https://docs.soliditylang.org/en/latest/control-structures.html#checked-or-unchecked-arithmetic.
                return low / denominator;
            }

            // Make sure the result is less than 2⁶⁴. Also prevents denominator == 0.
            if (denominator <= high) {
                panic(ternary(denominator == 0, DIVISION_BY_ZERO, UNDER_OVERFLOW));
            }

            ///////////////////////////////////////////////
            // 128 by 64 division.
            ///////////////////////////////////////////////

            // Make division exact by subtracting the remainder from [high low].
            uint64 remainder;
            // Compute remainder using mulmod.
            remainder = mulmod(x, y, denominator);

            // Subtract 64 bit number from 128 bit number.
            high = high - ternary(remainder > low, 1, 0);
            low = low - remainder;

            // Factor powers of two out of denominator and compute largest power of two divisor of denominator.
            // Always >= 1. See https://cs.stackexchange.com/q/138556/92363.

            uint64 twos = denominator & (0 - denominator);
            // Divide denominator by twos.
            denominator = denominator / twos;

            // Divide [high low] by twos.
            low = low / twos;

            // Flip twos such that it is 2⁶⁴ / twos. If twos is zero, then it becomes one.
            twos = ((0 - twos) / twos) + 1;

            // Shift in bits from high into low.
            low |= high * twos;

            // Invert denominator mod 2⁶⁴. Now that denominator is an odd number, it has an inverse modulo 2⁶⁴ such
            // that denominator * inv ≡ 1 mod 2⁶⁴. Compute the inverse by starting with a seed that is correct for
            // four bits. That is, denominator * inv ≡ 1 mod 2⁴.
            uint64 inverse = (3 * denominator) ^ 2;

            // Use the Newton-Raphson iteration to improve the precision. Thanks to Hensel's lifting lemma, this also
            // works in modular arithmetic, doubling the correct bits in each step.
            inverse *= 2 - denominator * inverse; // inverse mod 2⁸
            inverse *= 2 - denominator * inverse; // inverse mod 2¹⁶
            inverse *= 2 - denominator * inverse; // inverse mod 2³²
            inverse *= 2 - denominator * inverse; // inverse mod 2⁶⁴

            // Because the division is now exact we can divide by multiplying with the modular inverse of denominator.
            // This will give us the correct result modulo 2⁶⁴. Since the preconditions guarantee that the outcome is
            // less than 2⁶⁴, this is the final result. We don't need to compute the high bits of the result and high
            // is no longer required.
            result = low * inverse;
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
     * @dev Calculates floor(x * y >> n) with full precision. Throws if result overflows a uint64.
     */
    function mulShr(uint64 x, uint64 y, uint8 n) internal pure returns (uint64 result) {
        unchecked {
            (uint64 high, uint64 low) = mul512(x, y);
            if (high >= uint64(uint64(1) << n)) {
                panic(UNDER_OVERFLOW);
            }
            return (high << (64 - n)) | (low >> n);
        }
    }

    /**
     * @dev Calculates x * y >> n with full precision, following the selected rounding direction.
     */
    function mulShr(uint64 x, uint64 y, uint8 n, Rounding rounding) internal pure returns (uint64) {
        return mulShr(x, y, n) + toUint(unsignedRoundsUp(rounding) && mulmod(x, y, uint64(uint64(1) << n)) > 0);
    }

    /**
     * @dev Calculate the modular multiplicative inverse of a number in Z/nZ.
     *
     * If n is a prime, then Z/nZ is a field. In that case all elements are inversible, except 0.
     * If n is not a prime, then Z/nZ is not a field, and some elements might not be inversible.
     *
     * If the input value is not inversible, 0 is returned.
     *
     * NOTE: If you know for sure that n is (big) a prime, it may be cheaper to use Fermat's little theorem and get the
     * inverse using `Math.modExp(a, n - 2, n)`. See {invModPrime}.
     */
    function invMod(uint64 a, uint64 n) internal pure returns (uint64) {
        unchecked {
            if (n == 0) return 0;

            // The inverse modulo is calculated using the Extended Euclidean Algorithm (iterative version)
            // Used to compute integers x and y such that: ax + ny = gcd(a, n).
            // When the gcd is 1, then the inverse of a modulo n exists and it's x.
            // ax + ny = 1
            // ax = 1 + (-y)n
            // ax ≡ 1 (mod n) # x is the inverse of a modulo n

            // If the remainder is 0 the gcd is n right away.
            uint64 remainder = a % n;
            uint64 gcd = n;

            // Therefore the initial coefficients are:
            // ax + ny = gcd(a, n) = n
            // 0a + 1n = n
            int64 x = 0;
            int64 y = 1;

            while (remainder != 0) {
                uint64 quotient = gcd / remainder;

                (gcd, remainder) = (
                    // The old remainder is the next gcd to try.
                    remainder,
                    // Compute the next remainder.
                    // Can't overflow given that (a % gcd) * (gcd // (a % gcd)) <= gcd
                    // where gcd is at most n (capped to type(uint64).max)
                    gcd - remainder * quotient
                );

                (x, y) = (
                    // Increment the coefficient of a.
                    y,
                    // Decrement the coefficient of n.
                    // Can overflow, but the result is casted to uint64 so that the
                    // next value of y is "wrapped around" to a value between 0 and n - 1.
                    x - y * int64(quotient)
                );
            }

            if (gcd != 1) return 0; // No inverse exists.
            return ternary(x < 0, n - uint64(-x), uint64(x)); // Wrap the result if it's negative.
        }
    }

    /**
     * @dev Variant of {invMod}. More efficient, but only works if `p` is known to be a prime greater than `2`.
     *
     * From https://en.wikipedia.org/wiki/Fermat%27s_little_theorem[Fermat's little theorem], we know that if p is
     * prime, then `a**(p-1) ≡ 1 mod p`. As a consequence, we have `a * a**(p-2) ≡ 1 mod p`, which means that
     * `a**(p-2)` is the modular multiplicative inverse of a in Fp.
     *
     * NOTE: this function does NOT check that `p` is a prime greater than `2`.
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
     * - underlying staticcall to precompile must succeed
     *
     * IMPORTANT: The result is only valid if the underlying call succeeds. When using this function, make
     * sure the chain you're using it on supports the precompiled contract for modular exponentiation
     * at address 0x05 as specified in https://eips.ethereum.org/EIPS/eip-198[EIP-198]. Otherwise,
     * the underlying function will succeed given the lack of a revert, but the result may be incorrectly
     * interpreted as 0.
     */
    function modExp(uint64 b, uint64 e, uint64 m) internal view returns (uint64) {
        (bool success, uint64 result) = tryModExp(b, e, m);
        if (!success) {
            panic(DIVISION_BY_ZERO);
        }
        return result;
    }

    /**
     * @dev Returns the modular exponentiation of the specified base, exponent and modulus (b ** e % m).
     * It includes a success flag indicating if the operation succeeded. Operation will be marked as failed if trying
     * to operate modulo 0 or if the underlying precompile reverted.
     *
     * IMPORTANT: The result is only valid if the success flag is true. When using this function, make sure the chain
     * you're using it on supports the precompiled contract for modular exponentiation at address 0x05 as specified in
     * https://eips.ethereum.org/EIPS/eip-198[EIP-198]. Otherwise, the underlying function will succeed given the lack
     * of a revert, but the result may be incorrectly interpreted as 0.
     */
    function tryModExp(uint64 b, uint64 e, uint64 m) internal view returns (bool success, uint64 result) {
        if (m == 0) return (false, 0);
        // Solana does not support the MODEXP precompile at address 0x05.
        // We implement modular exponentiation using exponentiation by squaring.
        success = true;
        result = 1;
        b = b % m;
        while (e > 0) {
            if (e % 2 == 1) {
                result = mulmod(result, b, m);
            }
            e = e >> 1;
            b = mulmod(b, b, m);
        }
    }

    /**
     * @dev Variant of {modExp} that supports inputs of arbitrary length.
     */
    function modExp(bytes memory b, bytes memory e, bytes memory m) internal view returns (bytes memory) {
        (bool success, bytes memory result) = tryModExp(b, e, m);
        if (!success) {
            panic(DIVISION_BY_ZERO);
        }
        return result;
    }

    /**
     * @dev Variant of {tryModExp} that supports inputs of arbitrary length.
     */
    function tryModExp(
        bytes memory b,
        bytes memory e,
        bytes memory m
    ) internal view returns (bool success, bytes memory result) {
        if (_zeroBytes(m)) return (false, new bytes(0));

        uint64 mLen = uint64(m.length);

        // Encode call args in result and move the free memory pointer
        result = abi.encodePacked(b.length, e.length, mLen, b, e, m);

        // Solana does not support the MODEXP precompile at address 0x05.
        // Return failure for arbitrary-length modExp.
        success = false;
        result = new bytes(0);
    }

    /**
     * @dev Returns whether the provided byte array is zero.
     */
    function _zeroBytes(bytes memory byteArray) private pure returns (bool) {
        for (uint64 i = 0; i < byteArray.length; ++i) {
            if (byteArray[i] != 0) {
                return false;
            }
        }
        return true;
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
            // Take care of easy edge cases when a == 0 or a == 1
            if (a <= 1) {
                return a;
            }

            // In this function, we use Newton's method to get a root of `f(x) := x² - a`. It involves building a
            // sequence x_n that converges toward sqrt(a). For each iteration x_n, we also define the error between
            // the current value as `ε_n = | x_n - sqrt(a) |`.
            //
            // For our first estimation, we consider `e` the smallest power of 2 which is bigger than the square root
            // of the target. (i.e. `2**(e-1) ≤ sqrt(a) < 2**e`). We know that `e ≤ 32` because `(2³²)² = 2⁶⁴` is
            // bigger than any uint64.
            //
            // By noticing that
            // `2**(e-1) ≤ sqrt(a) < 2**e → (2**(e-1))² ≤ a < (2**e)² → 2**(2*e-2) ≤ a < 2**(2*e)`
            // we can deduce that `e - 1` is `log2(a) / 2`. We can thus compute `x_n = 2**(e-1)` using a method similar
            // to the msb function.
            uint64 aa = a;
            uint64 xn = 1;

            if (aa >= (uint64(1) << 32)) {
                aa >>= 32;
                xn <<= 16;
            }
            if (aa >= (uint64(1) << 16)) {
                aa >>= 16;
                xn <<= 8;
            }
            if (aa >= (uint64(1) << 8)) {
                aa >>= 8;
                xn <<= 4;
            }
            if (aa >= (uint64(1) << 4)) {
                aa >>= 4;
                xn <<= 2;
            }
            if (aa >= (uint64(1) << 2)) {
                xn <<= 1;
            }

            // We now have x_n such that `x_n = 2**(e-1) ≤ sqrt(a) < 2**e = 2 * x_n`. This implies ε_n ≤ 2**(e-1).
            //
            // We can refine our estimation by noticing that the middle of that interval minimizes the error.
            // If we move x_n to equal 2**(e-1) + 2**(e-2), then we reduce the error to ε_n ≤ 2**(e-2).
            // This is going to be our x_0 (and ε_0)
            xn = (3 * xn) >> 1; // ε_0 := | x_0 - sqrt(a) | ≤ 2**(e-2)

            // From here, Newton's method give us:
            // x_{n+1} = (x_n + a / x_n) / 2
            //
            // One should note that:
            // x_{n+1}² - a = ((x_n + a / x_n) / 2)² - a
            //              = ((x_n² + a) / (2 * x_n))² - a
            //              = (x_n⁴ + 2 * a * x_n² + a²) / (4 * x_n²) - a
            //              = (x_n⁴ + 2 * a * x_n² + a² - 4 * a * x_n²) / (4 * x_n²)
            //              = (x_n⁴ - 2 * a * x_n² + a²) / (4 * x_n²)
            //              = (x_n² - a)² / (2 * x_n)²
            //              = ((x_n² - a) / (2 * x_n))²
            //              ≥ 0
            // Which proves that for all n ≥ 1, sqrt(a) ≤ x_n
            //
            // This gives us the proof of quadratic convergence of the sequence:
            // ε_{n+1} = | x_{n+1} - sqrt(a) |
            //         = | (x_n + a / x_n) / 2 - sqrt(a) |
            //         = | (x_n² + a - 2*x_n*sqrt(a)) / (2 * x_n) |
            //         = | (x_n - sqrt(a))² / (2 * x_n) |
            //         = | ε_n² / (2 * x_n) |
            //         = ε_n² / | (2 * x_n) |
            //
            // For the first iteration, we have a special case where x_0 is known:
            // ε_1 = ε_0² / | (2 * x_0) |
            //     ≤ (2**(e-2))² / (2 * (2**(e-1) + 2**(e-2)))
            //     ≤ 2**(2*e-4) / (3 * 2**(e-1))
            //     ≤ 2**(e-3) / 3
            //     ≤ 2**(e-3-log2(3))
            //     ≤ 2**(e-4.5)
            //
            // For the following iterations, we use the fact that, 2**(e-1) ≤ sqrt(a) ≤ x_n:
            // ε_{n+1} = ε_n² / | (2 * x_n) |
            //         ≤ (2**(e-k))² / (2 * 2**(e-1))
            //         ≤ 2**(2*e-2*k) / 2**e
            //         ≤ 2**(e-2*k)
            xn = (xn + a / xn) >> 1; // ε_1 := | x_1 - sqrt(a) | ≤ 2**(e-4.5)  -- special case, see above
            xn = (xn + a / xn) >> 1; // ε_2 := | x_2 - sqrt(a) | ≤ 2**(e-9)    -- general case with k = 4.5
            xn = (xn + a / xn) >> 1; // ε_3 := | x_3 - sqrt(a) | ≤ 2**(e-18)   -- general case with k = 9
            xn = (xn + a / xn) >> 1; // ε_4 := | x_4 - sqrt(a) | ≤ 2**(e-36)   -- general case with k = 18
            xn = (xn + a / xn) >> 1; // ε_5 := | x_5 - sqrt(a) | ≤ 2**(e-72)   -- general case with k = 36

            // Because e ≤ 32 (as discussed during the first estimation phase), we know have reached a precision
            // ε_5 ≤ 2**(e-72) < 1. Given we're operating on integers, then we can ensure that xn is now either
            // sqrt(a) or sqrt(a) + 1.
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
    function log2(uint64 x) internal pure returns (uint64 r) {
        // If value has upper 32 bits set, log2 result is at least 32
        r = toUint(x > 0xffffffff) << 5;
        // If upper 16 bits of 32-bit half set, add 16 to result
        r |= toUint((x >> r) > 0xffff) << 4;
        // If upper 8 bits of 16-bit half set, add 8 to result
        r |= toUint((x >> r) > 0xff) << 3;
        // If upper 4 bits of 8-bit half set, add 4 to result
        r |= toUint((x >> r) > 0xf) << 2;

        // Shifts value right by the current result and use it as an index into this lookup table:
        //
        // | x (4 bits) |  index  | table[index] = MSB position |
        // |------------|---------|-----------------------------|
        // |    0000    |    0    |        table[0] = 0         |
        // |    0001    |    1    |        table[1] = 0         |
        // |    0010    |    2    |        table[2] = 1         |
        // |    0011    |    3    |        table[3] = 1         |
        // |    0100    |    4    |        table[4] = 2         |
        // |    0101    |    5    |        table[5] = 2         |
        // |    0110    |    6    |        table[6] = 2         |
        // |    0111    |    7    |        table[7] = 2         |
        // |    1000    |    8    |        table[8] = 3         |
        // |    1001    |    9    |        table[9] = 3         |
        // |    1010    |   10    |        table[10] = 3        |
        // |    1011    |   11    |        table[11] = 3        |
        // |    1100    |   12    |        table[12] = 3        |
        // |    1101    |   13    |        table[13] = 3        |
        // |    1110    |   14    |        table[14] = 3        |
        // |    1111    |   15    |        table[15] = 3        |
        //
        // The lookup table is represented as a 32-byte value with the MSB positions for 0-15 in the last 16 bytes.
        // Use Solidity code instead of assembly for Solana compatibility.
        uint64 shifted = x >> r;
        uint64 lookup;
        if (shifted & 0x1 > 0) lookup = 0;
        else if (shifted & 0x2 > 0) lookup = 1;
        else if (shifted & 0x4 > 0) lookup = 2;
        else if (shifted & 0x8 > 0) lookup = 3;
        else lookup = 0;
        r |= lookup;
    }

    /**
     * @dev Return the log in base 2, following the selected rounding direction, of a positive value.
     * Returns 0 if given 0.
     */
    function log2(uint64 value, Rounding rounding) internal pure returns (uint64) {
        unchecked {
            uint64 result = log2(value);
            return result + toUint(unsignedRoundsUp(rounding) && uint64(1) << result < value);
        }
    }

    /**
     * @dev Return the log in base 10 of a positive value rounded towards zero.
     * Returns 0 if given 0.
     */
    function log10(uint64 value) internal pure returns (uint64) {
        uint64 result = 0;
        unchecked {
            if (value >= 100000000000000000000000000000000) {
                value /= 100000000000000000000000000000000;
                result += 32;
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
    function log256(uint64 x) internal pure returns (uint64 r) {
        // If value has upper 32 bits set, log2 result is at least 32
        r = toUint(x > 0xffffffff) << 5;
        // If upper 16 bits of 32-bit half set, add 16 to result
        r |= toUint((x >> r) > 0xffff) << 4;
        // If upper 8 bits of 16-bit half set, add 8 to result
        r |= toUint((x >> r) > 0xff) << 3;
        // Add 1 if upper 4 bits of 8-bit half set, and divide accumulated result by 8
        return (r >> 3) | toUint((x >> r) > 0xf);
    }

    /**
     * @dev Return the log in base 256, following the selected rounding direction, of a positive value.
     * Returns 0 if given 0.
     */
    function log256(uint64 value, Rounding rounding) internal pure returns (uint64) {
        unchecked {
            uint64 result = log256(value);
            return result + toUint(unsignedRoundsUp(rounding) && uint64(1) << (result << 3) < value);
        }
    }

    /**
     * @dev Returns whether a provided rounding mode is considered rounding up for unsigned integers.
     */
    function unsignedRoundsUp(Rounding rounding) internal pure returns (bool) {
        return uint8(rounding) % 2 == 1;
    }
}