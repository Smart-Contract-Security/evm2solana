// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @notice Arithmetic library with operations for fixed-point numbers.
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/utils/FixedPointMathLib.sol)
/// @author Modified from Solmate (https://github.com/transmissions11/solmate/blob/main/src/utils/FixedPointMathLib.sol)
library FixedPointMathLib {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The operation failed, as the output exceeds the maximum value of uint256.
    string constant ExpOverflow = "ExpOverflow";

    /// @dev The operation failed, as the output exceeds the maximum value of uint256.
    string constant FactorialOverflow = "FactorialOverflow";

    /// @dev The operation failed, due to an overflow.
    string constant RPowOverflow = "RPowOverflow";

    /// @dev The mantissa is too big to fit.
    string constant MantissaOverflow = "MantissaOverflow";

    /// @dev The operation failed, due to an multiplication overflow.
    string constant MulWadFailed = "MulWadFailed";

    /// @dev The operation failed, due to an multiplication overflow.
    string constant SMulWadFailed = "SMulWadFailed";

    /// @dev The operation failed, either due to a multiplication overflow, or a division by a zero.
    string constant DivWadFailed = "DivWadFailed";

    /// @dev The operation failed, either due to a multiplication overflow, or a division by a zero.
    string constant SDivWadFailed = "SDivWadFailed";

    /// @dev The operation failed, either due to a multiplication overflow, or a division by a zero.
    string constant MulDivFailed = "MulDivFailed";

    /// @dev The division failed, as the denominator is zero.
    string constant DivFailed = "DivFailed";

    /// @dev The full precision multiply-divide operation failed, either due
    /// to the result being larger than 256 bits, or a division by a zero.
    string constant FullMulDivFailed = "FullMulDivFailed";

    /// @dev The output is undefined, as the input is less-than-or-equal to zero.
    string constant LnWadUndefined = "LnWadUndefined";

    /// @dev The input outside the acceptable domain.
    string constant OutOfDomain = "OutOfDomain";

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The scalar of ETH and most ERC20s.
    uint256 internal constant WAD = 1e18;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*              SIMPLIFIED FIXED POINT OPERATIONS             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Equivalent to `(x * y) / WAD` rounded down.
    function mulWad(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked {
            if (!(y == 0 || x <= type(uint256).max / y)) {
                revert(MulWadFailed);
            }
            z = (x * y) / WAD;
        }
    }

    /// @dev Equivalent to `(x * y) / WAD` rounded down.
    function sMulWad(int256 x, int256 y) internal pure returns (int256 z) {
        unchecked {
            z = x * y;
            if (!((x == 0 || z / x == y) && !(x == -1 && y == type(int256).min))) {
                revert(SMulWadFailed);
            }
            z = z / int256(WAD);
        }
    }

    /// @dev Equivalent to `(x * y) / WAD` rounded down, but without overflow checks.
    function rawMulWad(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked {
            z = (x * y) / WAD;
        }
    }

    /// @dev Equivalent to `(x * y) / WAD` rounded down, but without overflow checks.
    function rawSMulWad(int256 x, int256 y) internal pure returns (int256 z) {
        unchecked {
            z = (x * y) / int256(WAD);
        }
    }

    /// @dev Equivalent to `(x * y) / WAD` rounded up.
    function mulWadUp(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked {
            if (!(y == 0 || x <= type(uint256).max / y)) {
                revert(MulWadFailed);
            }
            uint256 prod = x * y;
            z = prod / WAD;
            if (prod % WAD != 0) {
                z++;
            }
        }
    }

    /// @dev Equivalent to `(x * y) / WAD` rounded up, but without overflow checks.
    function rawMulWadUp(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked {
            uint256 prod = x * y;
            z = prod / WAD;
            if (prod % WAD != 0) {
                z++;
            }
        }
    }

    /// @dev Equivalent to `(x * WAD) / y` rounded down.
    function divWad(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked {
            if (!(y != 0 && x <= type(uint256).max / WAD)) {
                revert(DivWadFailed);
            }
            z = (x * WAD) / y;
        }
    }

    /// @dev Equivalent to `(x * WAD) / y` rounded down.
    function sDivWad(int256 x, int256 y) internal pure returns (int256 z) {
        unchecked {
            z = x * int256(WAD);
            if (!(y != 0 && (z / int256(WAD) == x))) {
                revert(SDivWadFailed);
            }
            z = z / y;
        }
    }

    /// @dev Equivalent to `(x * WAD) / y` rounded down, but without overflow and divide by zero checks.
    function rawDivWad(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked {
            z = (x * WAD) / y;
        }
    }

    /// @dev Equivalent to `(x * WAD) / y` rounded down, but without overflow and divide by zero checks.
    function rawSDivWad(int256 x, int256 y) internal pure returns (int256 z) {
        unchecked {
            z = (x * int256(WAD)) / y;
        }
    }

    /// @dev Equivalent to `(x * WAD) / y` rounded up.
    function divWadUp(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked {
            if (!(y != 0 && x <= type(uint256).max / WAD)) {
                revert(DivWadFailed);
            }
            uint256 prod = x * WAD;
            z = prod / y;
            if (prod % y != 0) {
                z++;
            }
        }
    }

    /// @dev Equivalent to `(x * WAD) / y` rounded up, but without overflow and divide by zero checks.
    function rawDivWadUp(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked {
            uint256 prod = x * WAD;
            z = prod / y;
            if (prod % y != 0) {
                z++;
            }
        }
    }

    /// @dev Equivalent to `x` to the power of `y`.
    /// because `x ** y = (e ** ln(x)) ** y = e ** (ln(x) * y)`.
    function powWad(int256 x, int256 y) internal pure returns (int256) {
        // Using `ln(x)` means `x` must be greater than 0.
        return expWad((lnWad(x) * y) / int256(WAD));
    }

    /// @dev Returns `exp(x)`, denominated in `WAD`.
    /// Credit to Remco Bloemen under MIT license: https://2π.com/22/exp-ln
    function expWad(int256 x) internal pure returns (int256 r) {
        unchecked {
            // When the result is less than 0.5 we return zero.
            // This happens when `x <= (log(1e-18) * 1e18) ~ -4.15e19`.
            if (x <= -41446531673892822313) return r;

            // When the result is greater than `(2**255 - 1) / 1e18` we can not represent it as
            // an int. This happens when `x >= floor(log((2**255 - 1) / 1e18) * 1e18) ≈ 135`.
            if (x >= 135305999368893231589) {
                revert(ExpOverflow);
            }

            // `x` is now in the range `(-42, 136) * 1e18`. Convert to `(-42, 136) * 2**96`
            // for more intermediate precision and a binary basis. This base conversion
            // is a multiplication by 1e18 / 2**96 = 5**18 / 2**78.
            x = (x << 78) / int256(5 ** 18);

            // Reduce range of x to (-½ ln 2, ½ ln 2) * 2**96 by factoring out powers
            // of two such that exp(x) = exp(x') * 2**k, where k is an integer.
            // Solving this gives k = round(x / log(2)) and x' = x - k * log(2).
            int256 k = ((x << 96) / 54916777467707473351141471128 + int256(2 ** 95)) >> 96;
            x = x - k * 54916777467707473351141471128;

            // `k` is in the range `[-61, 195]`.

            // Evaluate using a (6, 7)-term rational approximation.
            // `p` is made monic, we'll multiply by a scale factor later.
            int256 y = x + 1346386616545796478920950773328;
            y = ((y * x) >> 96) + 57155421227552351082224309758442;
            int256 p = y + x - 94201549194550492254356042504812;
            p = ((p * y) >> 96) + 28719021644029726153956944680412240;
            p = p * x + (4385272521454847904659076985693276 << 96);

            // We leave `p` in `2**192` basis so we don't need to scale it back up for the division.
            int256 q = x - 2855989394907223263936484059900;
            q = ((q * x) >> 96) + 50020603652535783019961831881945;
            q = ((q * x) >> 96) - 533845033583426703283633433725380;
            q = ((q * x) >> 96) + 3604857256930695427073651918091429;
            q = ((q * x) >> 96) - 14423608567350463180887372962807573;
            q = ((q * x) >> 96) + 26449188498355588339934803723976023;

            // Div in assembly because solidity adds a zero check despite the unchecked.
            // The q polynomial won't have zeros in the domain as all its roots are complex.
            // No scaling is necessary because p is already `2**96` too large.
            r = p / q;

            // r should be in the range `(0.09, 0.25) * 2**96`.

            // We now need to multiply r by:
            // - The scale factor `s ≈ 6.031367120`.
            // - The `2**k` factor from the range reduction.
            // - The `1e18 / 2**96` factor for base conversion.
            // We do this all at once, with an intermediate result in `2**213`
            // basis, so the final right shift is always by a positive amount.
            r = int256(
                (uint256(r) * 3822833074963236453042738258902158003155416615667) >> uint256(195 - k)
            );
        }
    }

    /// @dev Returns `ln(x)`, denominated in `WAD`.
    /// Credit to Remco Bloemen under MIT license: https://2π.com/22/exp-ln
    function lnWad(int256 x) internal pure returns (int256 r) {
        unchecked {
            // We want to convert `x` from `10**18` fixed point to `2**96` fixed point.
            // We do this by multiplying by `2**96 / 10**18`. But since
            // `ln(x * C) = ln(x) + ln(C)`, we can simply do nothing here
            // and add `ln(2**96 / 10**18)` at the end.

            // Compute `k = log2(x) - 96`, `r = 159 - k = 255 - log2(x) = 255 ^ log2(x)`.
            uint256 absX = uint256(x > 0 ? x : -x);
            r = int256(7) * int256(absX > 0xffffffffffffffffffffffffffffffff ? 1 : 0);
            r |= int256(6) * int256(absX > 0xffffffffffffffff ? 1 : 0);
            r |= int256(5) * int256(absX > 0xffffffff ? 1 : 0);
            r |= int256(4) * int256(absX > 0xffff ? 1 : 0);
            r |= int256(3) * int256(absX > 0xff ? 1 : 0);
            // We place the check here for more optimal stack operations.
            if (x <= 0) {
                revert(LnWadUndefined);
            }
            // forgefmt: disable-next-item
            r = r ^ int256(uint256(bytes1(uint8(0xf8f9f9faf9fdfafbf9fdfcfdfafbfcfef9fafdfafcfcfbfefafafcfbffffffff >> ((absX >> uint256(r)) & 0x1f)))));

            // Reduce range of x to (1, 2) * 2**96
            // ln(2^k * x) = k * ln(2) + ln(x)
            x = int256((uint256(x) << uint256(r)) >> 159);

            // Evaluate using a (8, 8)-term rational approximation.
            // `p` is made monic, we will multiply by a scale factor later.
            // forgefmt: disable-next-item
            int256 p = int256((uint256(43456485725739037958740375743393 +
                uint256((uint256(24828157081833163892658089445524 +
                uint256((uint256(3273285459638523848632254066296) * uint256(x)) >> 96)) * uint256(x)) >> 96)) * uint256(x)) >> 96) - 11111509109440967052023855526967;
            p = int256((uint256(p) * uint256(x)) >> 96) - 45023709667254063763336534515857;
            p = int256((uint256(p) * uint256(x)) >> 96) - 14706773417378608786704636184526;
            p = p * x - int256(795164235651350426258249787498 << 96);
            // We leave `p` in `2**192` basis so we don't need to scale it back up for the division.

            // `q` is monic by convention.
            int256 q = x + 5573035233440673466300451813936;
            q = int256((uint256(q) * uint256(x)) >> 96) + 71694874799317883764090561454958;
            q = int256((uint256(q) * uint256(x)) >> 96) + 283447036172924575727196451306956;
            q = int256((uint256(q) * uint256(x)) >> 96) + 401686690394027663651624208769553;
            q = int256((uint256(q) * uint256(x)) >> 96) + 204048457590392012362485061816622;
            q = int256((uint256(q) * uint256(x)) >> 96) + 31853899698501571402653359427138;
            q = int256((uint256(q) * uint256(x)) >> 96) + 909429971244387300277376558375;

            // `p / q` is in the range `(0, 0.125) * 2**96`.

            // Finalization, we need to:
            // - Multiply by the scale factor `s = 5.549…`.
            // - Add `ln(2**96 / 10**18)`.
            // - Add `k * ln(2)`.
            // - Multiply by `10**18 / 2**96 = 5**18 >> 78`.

            // The q polynomial is known not to have zeros in the domain.
            // No scaling required because p is already `2**96` too large.
            p = p / q;
            // Multiply by the scaling factor: `s * 5**18 * 2**96`, base is now `5**18 * 2**192`.
            p = int256(uint256(p) * 1677202110996718588342820967067443963516166);
            // Add `ln(2) * k * 5**18 * 2**192`.
            // forgefmt: disable-next-item
            p = int256(uint256(16597577552685614221487285958193947469193820559219878177908093499208371) * uint256(159 - r) + uint256(p));
            // Add `ln(2**96 / 10**18) * 5**18 * 2**192`.
            p = int256(uint256(p) + 600920179829731861736702779321621459595472258049074101567377883020018308);
            // Base conversion: mul `2**18 / 2**192`.
            r = int256(uint256(p) >> 174);
        }
    }

    /// @dev Returns `W_0(x)`, denominated in `WAD`.
    /// See: https://en.wikipedia.org/wiki/Lambert_W_function
    /// a.k.a. Product log function. This is an approximation of the principal branch.
    function lambertW0Wad(int256 x) internal pure returns (int256 w) {
        // forgefmt: disable-next-item
        unchecked {
            if ((w = x) <= -367879441171442322) revert(OutOfDomain); // `x` less than `-1/e`.
            int256 wad = int256(WAD);
            int256 p = x;
            uint256 c; // Whether we need to avoid catastrophic cancellation.
            uint256 i = 4; // Number of iterations.
            if (w <= 0x1ffffffffffff) {
                if (-0x4000000000000 <= w) {
                    i = 1; // Inputs near zero only take one step to converge.
                } else if (w <= -0x3ffffffffffffff) {
                    i = 32; // Inputs near `-1/e` take very long to converge.
                }
            } else if (uint256(w) >> 63 == 0) {
                // Inline log2 for more performance, since the range is small.
                uint256 v = uint256(w) >> 49;
                uint256 l = v > 0xff ? 3 : 0;
                l |= uint256(bytes1(uint8(0x0706060506020504060203020504030106050205030304010505030400000000 >> ((v >> l) & 0x1f)))) & 0xff;
                l += 49;
                w = int256((uint256(w) << 7) / uint256(uint8(0x0303030303030303040506080c13 >> (31 - l))));
                c = l > 60 ? 1 : 0;
                i = 2 + (l > 53 ? 1 : 0) + c;
            } else {
                int256 ll = lnWad(w = lnWad(w));
                // `w = ln(x) - ln(ln(x)) + b * ln(ln(x)) / ln(x)`.
                w = (ll * 1023715080943847266) / w + (w - ll);
                i = 3 + (uint256(x) >> 68 == 0 ? 1 : 0);
                c = uint256(x) >> 143 == 0 ? 1 : 0;
                if (c == 0) {
                    do { // If `x` is big, use Newton's so that intermediate values won't overflow.
                        int256 e = expWad(w);
                        int256 t = (w * e) / wad;
                        w = w - ((t - x) * wad) / (e + t);
                        if (p <= w) break;
                        p = w;
                    } while (--i != 0);
                    if (w > 2) w = w - 1;
                    return w;
                }
            }
            do { // Otherwise, use Halley's for faster convergence.
                int256 e = expWad(w);
                int256 t = w + wad;
                int256 s = (w * e) - (x * wad);
                w = w - (s * wad) / (e * t - ((t + wad) * s) / (t + t));
                if (p <= w) break;
                p = w;
            } while (--i != c);
            if (w > 2) w = w - 1;
            // For certain ranges of `x`, we'll use the quadratic-rate recursive formula of
            // R. Iacono and J.P. Boyd for the last iteration, to avoid catastrophic cancellation.
            if (c != 0) {
                int256 t = w | 1;
                x = (x * wad) / t;
                x = t * (wad + lnWad(x));
                w = x / (wad + t);
            }
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  GENERAL NUMBER UTILITIES                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Calculates `floor(x * y / d)` with full precision.
    /// Throws if result overflows a uint256 or when `d` is zero.
    /// Credit to Remco Bloemen under MIT license: https://2π.com/21/muldiv
    function fullMulDiv(uint256 x, uint256 y, uint256 d) internal pure returns (uint256 result) {
        unchecked {
            // 512-bit multiply `[p1 p0] = x * y`.
            // Compute the product mod `2**256` and mod `2**256 - 1`
            // then use the Chinese Remainder Theorem to reconstruct
            // the 512 bit result. The result is stored in two 256
            // variables such that `product = p1 * 2**256 + p0`.

            // Least significant 256 bits of the product.
            uint256 p0 = x * y;
            uint256 mm = mulmod(x, y, type(uint256).max);
            // Most significant 256 bits of the product.
            uint256 p1 = mm - p0 - (mm < p0 ? 1 : 0);

            // Handle non-overflow cases, 256 by 256 division.
            if (p1 == 0) {
                if (d == 0) {
                    revert(FullMulDivFailed);
                }
                return p0 / d;
            }

            // Make sure the result is less than `2**256`. Also prevents `d == 0`.
            if (d <= p1) {
                revert(FullMulDivFailed);
            }

            /*------------------- 512 by 256 division --------------------*/

            // Make division exact by subtracting the remainder from `[p1 p0]`.
            // Compute remainder using mulmod.
            uint256 r = mulmod(x, y, d);
            // `t` is the least significant bit of `d`.
            // Always greater or equal to 1.
            uint256 t = d & -d;
            // Divide `d` by `t`, which is a power of two.
            d = d / t;
            // Invert `d mod 2**256`
            // Now that `d` is an odd number, it has an inverse
            // modulo `2**256` such that `d * inv = 1 mod 2**256`.
            // Compute the inverse by starting with a seed that is correct
            // correct for four bits. That is, `d * inv = 1 mod 2**4`.
            uint256 inv = (3 * d) ^ 2;
            // Now use Newton-Raphson iteration to improve the precision.
            // Thanks to Hensel's lifting lemma, this also works in modular
            // arithmetic, doubling the correct bits in each step.
            inv = inv * (2 - d * inv); // inverse mod 2**8
            inv = inv * (2 - d * inv); // inverse mod 2**16
            inv = inv * (2 - d * inv); // inverse mod 2**32
            inv = inv * (2 - d * inv); // inverse mod 2**64
            inv = inv * (2 - d * inv); // inverse mod 2**128
            result = (p1 - (r > p0 ? 1 : 0)) * ((type(uint256).max / t) + 1) + (p0 - r) / t;
            result = result * inv * (2 - d * inv);
        }
    }

    /// @dev Calculates `floor(x * y / d)` with full precision, rounded up.
    /// Throws if result overflows a uint256 or when `d` is zero.
    /// Credit to Uniswap-v3-core under MIT license:
    /// https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/FullMath.sol
    function fullMulDivUp(uint256 x, uint256 y, uint256 d) internal pure returns (uint256 result) {
        result = fullMulDiv(x, y, d);
        unchecked {
            if (mulmod(x, y, d) != 0) {
                result++;
                if (result == 0) {
                    revert(FullMulDivFailed);
                }
            }
        }
    }

    /// @dev Returns `floor(x * y / d)`.
    /// Reverts if `x * y` overflows, or `d` is zero.
    function mulDiv(uint256 x, uint256 y, uint256 d) internal pure returns (uint256 z) {
        unchecked {
            if (!(d != 0 && (y == 0 || x <= type(uint256).max / y))) {
                revert(MulDivFailed);
            }
            z = (x * y) / d;
        }
    }

    /// @dev Returns `ceil(x * y / d)`.
    /// Reverts if `x * y` overflows, or `d` is zero.
    function mulDivUp(uint256 x, uint256 y, uint256 d) internal pure returns (uint256 z) {
        unchecked {
            if (!(d != 0 && (y == 0 || x <= type(uint256).max / y))) {
                revert(MulDivFailed);
            }
            uint256 prod = x * y;
            z = prod / d;
            if (prod % d != 0) {
                z++;
            }
        }
    }

    /// @dev Returns `ceil(x / d)`.
    /// Reverts if `d` is zero.
    function divUp(uint256 x, uint256 d) internal pure returns (uint256 z) {
        unchecked {
            if (d == 0) {
                revert(DivFailed);
            }
            z = x / d;
            if (x % d != 0) {
                z++;
            }
        }
    }

    /// @dev Returns `max(0, x - y)`.
    function zeroFloorSub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked {
            z = x > y ? x - y : 0;
        }
    }

    /// @dev Exponentiate `x` to `y` by squaring, denominated in base `b`.
    /// Reverts if the computation overflows.
    function rpow(uint256 x, uint256 y, uint256 b) internal pure returns (uint256 z) {
        unchecked {
            z = y == 0 ? b : 0;
            if (x != 0) {
                z = (y & 1) == 0 ? b : x;
                uint256 half = b / 2;
                y = y >> 1;
                while (y != 0) {
                    uint256 xx = x * x;
                    uint256 xxRound = xx + half;
                    if (xxRound < xx || x > type(uint128).max) {
                        revert(RPowOverflow);
                    }
                    x = xxRound / b;
                    if ((y & 1) != 0) {
                        uint256 zx = z * x;
                        uint256 zxRound = zx + half;
                        if (zx / x != z || zxRound < zx) {
                            if (x != 0) {
                                revert(RPowOverflow);
                            }
                        }
                        z = zxRound / b;
                    }
                    y = y >> 1;
                }
            }
        }
    }

    /// @dev Returns the square root of `x`.
    function sqrt(uint256 x) internal pure returns (uint256 z) {
        unchecked {
            // `floor(sqrt(2**15)) = 181`. `sqrt(2**15) - 181 = 2.84`.
            z = 181; // The "correct" value is 1, but this saves a multiplication later.

            // This segment is to get a reasonable initial estimate for the Babylonian method. With a bad
            // start, the correct # of bits increases ~linearly each iteration instead of ~quadratically.

            // Let `y = x / 2**r`. We check `y >= 2**(k + 8)`
            // but shift right by `k` bits to ensure that if `x >= 256`, then `y >= 256`.
            uint256 r = x > 0xffffffffffffffffffffffffffffffffff ? 7 : 0;
            r |= (x >> r) > 0xffffffffffffffffff ? 6 : 0;
            r |= (x >> r) > 0xffffffffff ? 5 : 0;
            r |= (x >> r) > 0xffffff ? 4 : 0;
            z = z << (r >> 1);

            // Goal was to get `z*z*y` within a small factor of `x`. More iterations could
            // get y in a tighter range. Currently, we will have y in `[256, 256*(2**16))`.
            // We ensured `y >= 256` so that the relative difference between `y` and `y+1` is small.
            // That's not possible if `x < 256` but we can just verify those cases exhaustively.

            // Now, `z*z*y <= x < z*z*(y+1)`, and `y <= 2**(16+8)`, and either `y >= 256`, or `x < 256`.
            // Correctness can be checked exhaustively for `x < 256`, so we assume `y >= 256`.
            // Then `z*sqrt(y)` is within `sqrt(257)/sqrt(256)` of `sqrt(x)`, or about 20bps.

            // For `s` in the range `[1/256, 256]`, the estimate `f(s) = (181/1024) * (s+1)`
            // is in the range `(1/2.84 * sqrt(s), 2.84 * sqrt(s))`,
            // with largest error when `s = 1` and when `s = 256` or `1/256`.

            // Since `y` is in `[256, 256*(2**16))`, let `a = y/65536`, so that `a` is in `[1/256, 256)`.
            // Then we can estimate `sqrt(y)` using
            // `sqrt(65536) * 181/1024 * (a + 1) = 181/4 * (y + 65536)/65536 = 181 * (y + 65536)/2**18`.

            // There is no overflow risk here since `y < 2**136` after the first branch above.
            z = (z * ((x >> r) + 65536)) >> 18; // A `mul()` is saved from starting `z` at 181.

            // Given the worst case multiplicative error of 2.84 above, 7 iterations should be enough.
            z = (z + x / z) >> 1;
            z = (z + x / z) >> 1;
            z = (z + x / z) >> 1;
            z = (z + x / z) >> 1;
            z = (z + x / z) >> 1;
            z = (z + x / z) >> 1;
            z = (z + x / z) >> 1;

            // If `x+1` is a perfect square, the Babylonian method cycles between
            // `floor(sqrt(x))` and `ceil(sqrt(x))`. This statement ensures we return floor.
            // See: https://en.wikipedia.org/wiki/Integer_square_root#Using_only_integer_division
            if (z > x / z) {
                z--;
            }
        }
    }

    /// @dev Returns the cube root of `x`.
    /// Credit to bout3fiddy and pcaversaccio under AGPLv3 license:
    /// https://github.com/pcaversaccio/snekmate/blob/main/src/utils/Math.vy
    function cbrt(uint256 x) internal pure returns (uint256 z) {
        unchecked {
            uint256 r = x > 0xffffffffffffffffffffffffffffffff ? 7 : 0;
            r |= (x >> r) > 0xffffffffffffffff ? 6 : 0;
            r |= (x >> r) > 0xffffffff ? 5 : 0;
            r |= (x >> r) > 0xffff ? 4 : 0;
            r |= (x >> r) > 0xff ? 3 : 0;

            z = (1 << (r / 3)) * ((x >> r) > 0xf ? 0xf : 1) / (7 ^ (r % 3));

            z = (x / (z * z) + z + z) / 3;
            z = (x / (z * z) + z + z) / 3;
            z = (x / (z * z) + z + z) / 3;
            z = (x / (z * z) + z + z) / 3;
            z = (x / (z * z) + z + z) / 3;
            z = (x / (z * z) + z + z) / 3;
            z = (x / (z * z) + z + z) / 3;

            if (z > x / (z * z)) {
                z--;
            }
        }
    }

    /// @dev Returns the square root of `x`, denominated in `WAD`.
    function sqrtWad(uint256 x) internal pure returns (uint256 z) {
        unchecked {
            z = 10 ** 9;
            if (x <= type(uint256).max / 10 ** 36 - 1) {
                x *= 10 ** 18;
                z = 1;
            }
            z *= sqrt(x);
        }
    }

    /// @dev Returns the cube root of `x`, denominated in `WAD`.
    function cbrtWad(uint256 x) internal pure returns (uint256 z) {
        unchecked {
            z = 10 ** 12;
            if (x <= (type(uint256).max / 10 ** 36) * 10 ** 18 - 1) {
                if (x >= type(uint256).max / 10 ** 36) {
                    x *= 10 ** 18;
                    z = 10 ** 6;
                } else {
                    x *= 10 ** 36;
                    z = 1;
                }
            }
            z *= cbrt(x);
        }
    }

    /// @dev Returns the factorial of `x`.
    function factorial(uint256 x) internal pure returns (uint256 result) {
        unchecked {
            if (x >= 58) {
                revert(FactorialOverflow);
            }
            result = 1;
            while (x != 0) {
                result *= x;
                x--;
            }
        }
    }

    /// @dev Returns the log2 of `x`.
    /// Equivalent to computing the index of the most significant bit (MSB) of `x`.
    /// Returns 0 if `x` is zero.
    function log2(uint256 x) internal pure returns (uint256 r) {
        unchecked {
            r = x > 0xffffffffffffffffffffffffffffffff ? 7 : 0;
            r |= (x >> r) > 0xffffffffffffffff ? 6 : 0;
            r |= (x >> r) > 0xffffffff ? 5 : 0;
            r |= (x >> r) > 0xffff ? 4 : 0;
            r |= (x >> r) > 0xff ? 3 : 0;
            // forgefmt: disable-next-item
            r |= uint256(bytes1(uint8(0x0706060506020504060203020504030106050205030304010505030400000000 >> ((x >> r) & 0x1f)))) & 0xff;
        }
    }

    /// @dev Returns the log2 of `x`, rounded up.
    /// Returns 0 if `x` is zero.
    function log2Up(uint256 x) internal pure returns (uint256 r) {
        r = log2(x);
        unchecked {
            if ((1 << r) < x) {
                r++;
            }
        }
    }

    /// @dev Returns the log10 of `x`.
    /// Returns 0 if `x` is zero.
    function log10(uint256 x) internal pure returns (uint256 r) {
        unchecked {
            r = 0;
            if (x >= 100000000000000000000000000000000000000) {
                x /= 100000000000000000000000000000000000000;
                r = 38;
            }
            if (x >= 100000000000000000000) {
                x /= 100000000000000000000;
                r += 20;
            }
            if (x >= 10000000000) {
                x /= 10000000000;
                r += 10;
            }
            if (x >= 100000) {
                x /= 100000;
                r += 5;
            }
            if (x >= 10) r++;
            if (x >= 100) r++;
            if (x >= 1000) r++;
            if (x >= 10000) r++;
        }
    }

    /// @dev Returns the log10 of `x`, rounded up.
    /// Returns 0 if `x` is zero.
    function log10Up(uint256 x) internal pure returns (uint256 r) {
        r = log10(x);
        unchecked {
            if (10 ** r < x) {
                r++;
            }
        }
    }

    /// @dev Returns the log256 of `x`.
    /// Returns 0 if `x` is zero.
    function log256(uint256 x) internal pure returns (uint256 r) {
        unchecked {
            r = x > 0xffffffffffffffffffffffffffffffff ? 7 : 0;
            r |= (x >> r) > 0xffffffffffffffff ? 6 : 0;
            r |= (x >> r) > 0xffffffff ? 5 : 0;
            r |= (x >> r) > 0xffff ? 4 : 0;
            r = (r >> 3) | ((x >> r) > 0xff ? 1 : 0);
        }
    }

    /// @dev Returns the log256 of `x`, rounded up.
    /// Returns 0 if `x` is zero.
    function log256Up(uint256 x) internal pure returns (uint256 r) {
        r = log256(x);
        unchecked {
            if ((1 << (r * 8)) < x) {
                r++;
            }
        }
    }

    /// @dev Returns the scientific notation format `mantissa * 10 ** exponent` of `x`.
    /// Useful for compressing prices (e.g. using 25 bit mantissa and 7 bit exponent).
    function sci(uint256 x) internal pure returns (uint256 mantissa, uint256 exponent) {
        unchecked {
            mantissa = x;
            exponent = 0;
            if (mantissa != 0) {
                if (mantissa % 1000000000000000000000000000000000 == 0) {
                    mantissa /= 1000000000000000000000000000000000;
                    exponent = 33;
                }
                if (mantissa % 10000000000000000000 == 0) {
                    mantissa /= 10000000000000000000;
                    exponent += 19;
                }
                if (mantissa % 1000000000000 == 0) {
                    mantissa /= 1000000000000;
                    exponent += 12;
                }
                if (mantissa % 1000000 == 0) {
                    mantissa /= 1000000;
                    exponent += 6;
                }
                if (mantissa % 10000 == 0) {
                    mantissa /= 10000;
                    exponent += 4;
                }
                if (mantissa % 100 == 0) {
                    mantissa /= 100;
                    exponent += 2;
                }
                if (mantissa % 10 == 0) {
                    mantissa /= 10;
                    exponent += 1;
                }
            }
        }
    }

    /// @dev Convenience function for packing `x` into a smaller number using `sci`.
    /// The `mantissa` will be in bits [7..255] (the upper 249 bits).
    /// The `exponent` will be in bits [0..6] (the lower 7 bits).
    /// Use `SafeCastLib` to safely ensure that the `packed` number is small
    /// enough to fit in the desired unsigned integer type:
    /// ```
    ///     uint32 packed = SafeCastLib.toUint32(FixedPointMathLib.packSci(777 ether));
    /// ```
    function packSci(uint256 x) internal pure returns (uint256 packed) {
        uint256 mantissa;
        uint256 exponent;
        (mantissa, exponent) = sci(x);
        if (mantissa > type(uint248).max) {
            revert(MantissaOverflow);
        }
        packed = (mantissa << 7) | exponent;
    }

    /// @dev Convenience function for unpacking a packed number from `packSci`.
    function unpackSci(uint256 packed) internal pure returns (uint256 unpacked) {
        unchecked {
            unpacked = (packed >> 7) * (10 ** (packed & 0x7f));
        }
    }

    /// @dev Returns the average of `x` and `y`.
    function avg(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked {
            z = (x & y) + ((x ^ y) >> 1);
        }
    }

    /// @dev Returns the average of `x` and `y`.
    function avg(int256 x, int256 y) internal pure returns (int256 z) {
        unchecked {
            z = (x >> 1) + (y >> 1) + (x & y & 1);
        }
    }

    /// @dev Returns the absolute value of `x`.
    function abs(int256 x) internal pure returns (uint256 z) {
        unchecked {
            z = x < 0 ? uint256(-x) : uint256(x);
        }
    }

    /// @dev Returns the absolute distance between `x` and `y`.
    function dist(int256 x, int256 y) internal pure returns (uint256 z) {
        unchecked {
            int256 diff = x - y;
            z = diff < 0 ? uint256(-diff) : uint256(diff);
        }
    }

    /// @dev Returns the minimum of `x` and `y`.
    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked {
            z = x < y ? x : y;
        }
    }

    /// @dev Returns the minimum of `x` and `y`.
    function min(int256 x, int256 y) internal pure returns (int256 z) {
        unchecked {
            z = x < y ? x : y;
        }
    }

    /// @dev Returns the maximum of `x` and `y`.
    function max(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked {
            z = x > y ? x : y;
        }
    }

    /// @dev Returns the maximum of `x` and `y`.
    function max(int256 x, int256 y) internal pure returns (int256 z) {
        unchecked {
            z = x > y ? x : y;
        }
    }

    /// @dev Returns `x`, bounded to `minValue` and `maxValue`.
    function clamp(uint256 x, uint256 minValue, uint256 maxValue)
        internal
        pure
        returns (uint256 z)
    {
        unchecked {
            z = x < minValue ? minValue : x;
            z = z > maxValue ? maxValue : z;
        }
    }

    /// @dev Returns `x`, bounded to `minValue` and `maxValue`.
    function clamp(int256 x, int256 minValue, int256 maxValue) internal pure returns (int256 z) {
        unchecked {
            z = x < minValue ? minValue : x;
            z = z > maxValue ? maxValue : z;
        }
    }

    /// @dev Returns greatest common divisor of `x` and `y`.
    function gcd(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked {
            z = x;
            while (y != 0) {
                uint256 t = y;
                y = z % y;
                z = t;
            }
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   RAW NUMBER OPERATIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Returns `x + y`, without checking for overflow.
    function rawAdd(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked {
            z = x + y;
        }
    }

    /// @dev Returns `x + y`, without checking for overflow.
    function rawAdd(int256 x, int256 y) internal pure returns (int256 z) {
        unchecked {
            z = x + y;
        }
    }

    /// @dev Returns `x - y`, without checking for underflow.
    function rawSub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked {
            z = x - y;
        }
    }

    /// @dev Returns `x - y`, without checking for underflow.
    function rawSub(int256 x, int256 y) internal pure returns (int256 z) {
        unchecked {
            z = x - y;
        }
    }

    /// @dev Returns `x * y`, without checking for overflow.
    function rawMul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked {
            z = x * y;
        }
    }

    /// @dev Returns `x * y`, without checking for overflow.
    function rawMul(int256 x, int256 y) internal pure returns (int256 z) {
        unchecked {
            z = x * y;
        }
    }

    /// @dev Returns `x / y`, returning 0 if `y` is zero.
    function rawDiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked {
            z = y == 0 ? 0 : x / y;
        }
    }

    /// @dev Returns `x / y`, returning 0 if `y` is zero.
    function rawSDiv(int256 x, int256 y) internal pure returns (int256 z) {
        unchecked {
            z = y == 0 ? 0 : x / y;
        }
    }

    /// @dev Returns `x % y`, returning 0 if `y` is zero.
    function rawMod(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked {
            z = y == 0 ? 0 : x % y;
        }
    }

    /// @dev Returns `x % y`, returning 0 if `y` is zero.
    function rawSMod(int256 x, int256 y) internal pure returns (int256 z) {
        unchecked {
            z = y == 0 ? 0 : x % y;
        }
    }

    /// @dev Returns `(x + y) % d`, return 0 if `d` if zero.
    function rawAddMod(uint256 x, uint256 y, uint256 d) internal pure returns (uint256 z) {
        unchecked {
            z = d == 0 ? 0 : addmod(x, y, d);
        }
    }

    /// @dev Returns `(x * y) % d`, return 0 if `d` if zero.
    function rawMulMod(uint256 x, uint256 y, uint256 d) internal pure returns (uint256 z) {
        unchecked {
            z = d == 0 ? 0 : mulmod(x, y, d);
        }
    }
}