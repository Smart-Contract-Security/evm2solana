// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Panic} from "../Panic.sol";

library Math {
    enum Rounding {
        Floor,
        Ceil,
        Trunc,
        Expand
    }

    function toUint(bool b) internal pure returns (uint256) {
        unchecked {
            return b ? 1 : 0;
        }
    }

    function add512(uint256 a, uint256 b) internal pure returns (uint256 high, uint256 low) {
        unchecked {
            low = a + b;
            high = low < a ? 1 : 0;
        }
    }

    function mul512(uint256 a, uint256 b) internal pure returns (uint256 high, uint256 low) {
        unchecked {
            uint256 mm = mulmod(a, b, type(uint256).max);
            low = a * b;
            high = mm - low;
            if (mm < low) {
                high -= 1;
            }
        }
    }

    function tryAdd(uint256 a, uint256 b) internal pure returns (bool success, uint256 result) {
        unchecked {
            uint256 c = a + b;
            success = c >= a;
            result = c * toUint(success);
        }
    }

    function trySub(uint256 a, uint256 b) internal pure returns (bool success, uint256 result) {
        unchecked {
            uint256 c = a - b;
            success = c <= a;
            result = c * toUint(success);
        }
    }

    function tryMul(uint256 a, uint256 b) internal pure returns (bool success, uint256 result) {
        unchecked {
            uint256 c = a * b;
            if (a == 0) {
                success = true;
            } else {
                success = (c / a) == b;
            }
            result = c * toUint(success);
        }
    }

    function tryDiv(uint256 a, uint256 b) internal pure returns (bool success, uint256 result) {
        unchecked {
            success = b > 0;
            if (success) {
                result = a / b;
            } else {
                result = 0;
            }
        }
    }

    function tryMod(uint256 a, uint256 b) internal pure returns (bool success, uint256 result) {
        unchecked {
            success = b > 0;
            if (success) {
                result = a % b;
            } else {
                result = 0;
            }
        }
    }

    function saturatingAdd(uint256 a, uint256 b) internal pure returns (uint256) {
        (bool success, uint256 result) = tryAdd(a, b);
        return ternary(success, result, type(uint256).max);
    }

    function saturatingSub(uint256 a, uint256 b) internal pure returns (uint256) {
        (, uint256 result) = trySub(a, b);
        return result;
    }

    function saturatingMul(uint256 a, uint256 b) internal pure returns (uint256) {
        (bool success, uint256 result) = tryMul(a, b);
        return ternary(success, result, type(uint256).max);
    }

    function ternary(bool condition, uint256 a, uint256 b) internal pure returns (uint256) {
        unchecked {
            return b ^ ((a ^ b) * toUint(condition));
        }
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return ternary(a > b, a, b);
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return ternary(a < b, a, b);
    }

    function average(uint256 a, uint256 b) internal pure returns (uint256) {
        unchecked {
            return (a & b) + (a ^ b) / 2;
        }
    }

    function ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b == 0) {
            Panic.panic(Panic.DIVISION_BY_ZERO);
        }
        unchecked {
            return toUint(a > 0) * ((a - 1) / b + 1);
        }
    }

    function mulDiv(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256 result) {
        unchecked {
            (uint256 high, uint256 low) = mul512(x, y);

            if (high == 0) {
                return low / denominator;
            }

            if (denominator <= high) {
                Panic.panic(ternary(denominator == 0, Panic.DIVISION_BY_ZERO, Panic.UNDER_OVERFLOW));
            }

            uint256 remainder = mulmod(x, y, denominator);

            if (remainder > low) {
                high -= 1;
            }
            low -= remainder;

            uint256 twos = denominator & (0 - denominator);
            denominator /= twos;
            low /= twos;
            twos = (type(uint256).max / twos) + 1;

            low |= high * twos;

            uint256 inverse = (3 * denominator) ^ 2;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;

            result = low * inverse;
            return result;
        }
    }

    function mulDiv(uint256 x, uint256 y, uint256 denominator, Rounding rounding) internal pure returns (uint256) {
        return mulDiv(x, y, denominator) + toUint(unsignedRoundsUp(rounding) && mulmod(x, y, denominator) > 0);
    }

    function mulShr(uint256 x, uint256 y, uint8 n) internal pure returns (uint256 result) {
        unchecked {
            (uint256 high, uint256 low) = mul512(x, y);
            if (high >= (uint256(1) << n)) {
                Panic.panic(Panic.UNDER_OVERFLOW);
            }
            return (high << (256 - n)) | (low >> n);
        }
    }

    function mulShr(uint256 x, uint256 y, uint8 n, Rounding rounding) internal pure returns (uint256) {
        return mulShr(x, y, n) + toUint(unsignedRoundsUp(rounding) && mulmod(x, y, uint256(1) << n) > 0);
    }

    function invMod(uint256 a, uint256 n) internal pure returns (uint256) {
        unchecked {
            if (n == 0) return 0;

            uint256 remainder = a % n;
            uint256 gcd = n;

            int256 x = 0;
            int256 y = 1;

            while (remainder != 0) {
                uint256 quotient = gcd / remainder;

                (gcd, remainder) = (
                    remainder,
                    gcd - remainder * quotient
                );

                (x, y) = (
                    y,
                    x - y * int256(quotient)
                );
            }

            if (gcd != 1) return 0;
            return ternary(x < 0, n - uint256(-x), uint256(x));
        }
    }

    function invModPrime(uint256 a, uint256 p) internal view returns (uint256) {
        unchecked {
            return Math.modExp(a, p - 2, p);
        }
    }

    function modExp(uint256 b, uint256 e, uint256 m) internal view returns (uint256) {
        (bool success, uint256 result) = tryModExp(b, e, m);
        if (!success) {
            Panic.panic(Panic.DIVISION_BY_ZERO);
        }
        return result;
    }

    function tryModExp(uint256 b, uint256 e, uint256 m) internal view returns (bool success, uint256 result) {
        if (m == 0) return (false, 0);
        // Solang does not support the MODEXP precompile (0x05) on Solana.
        // This function will always fail on Solana.
        // Return failure to indicate the operation is not supported.
        return (false, 0);
    }

    function modExp(bytes memory b, bytes memory e, bytes memory m) internal view returns (bytes memory) {
        (bool success, bytes memory result) = tryModExp(b, e, m);
        if (!success) {
            Panic.panic(Panic.DIVISION_BY_ZERO);
        }
        return result;
    }

    function tryModExp(
        bytes memory b,
        bytes memory e,
        bytes memory m
    ) internal view returns (bool success, bytes memory result) {
        if (_zeroBytes(m)) return (false, new bytes(0));
        // Solang does not support the MODEXP precompile (0x05) on Solana.
        // Return failure to indicate the operation is not supported.
        return (false, new bytes(0));
    }

    function _zeroBytes(bytes memory byteArray) private pure returns (bool) {
        for (uint256 i = 0; i < byteArray.length; ++i) {
            if (byteArray[i] != 0) {
                return false;
            }
        }
        return true;
    }

    function sqrt(uint256 a) internal pure returns (uint256) {
        unchecked {
            if (a <= 1) {
                return a;
            }

            uint256 aa = a;
            uint256 xn = 1;

            if (aa >= (uint256(1) << 128)) {
                aa >>= 128;
                xn <<= 64;
            }
            if (aa >= (uint256(1) << 64)) {
                aa >>= 64;
                xn <<= 32;
            }
            if (aa >= (uint256(1) << 32)) {
                aa >>= 32;
                xn <<= 16;
            }
            if (aa >= (uint256(1) << 16)) {
                aa >>= 16;
                xn <<= 8;
            }
            if (aa >= (uint256(1) << 8)) {
                aa >>= 8;
                xn <<= 4;
            }
            if (aa >= (uint256(1) << 4)) {
                aa >>= 4;
                xn <<= 2;
            }
            if (aa >= (uint256(1) << 2)) {
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

    function sqrt(uint256 a, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = sqrt(a);
            return result + toUint(unsignedRoundsUp(rounding) && result * result < a);
        }
    }

    function log2(uint256 x) internal pure returns (uint256 r) {
        r = toUint(x > 0xffffffffffffffffffffffffffffffff) << 7;
        r |= toUint((x >> r) > 0xffffffffffffffff) << 6;
        r |= toUint((x >> r) > 0xffffffff) << 5;
        r |= toUint((x >> r) > 0xffff) << 4;
        r |= toUint((x >> r) > 0xff) << 3;
        r |= toUint((x >> r) > 0xf) << 2;

        uint256 shifted = x >> r;
        uint8 lookup;
        if (shifted & 0x8 != 0) {
            lookup = 3;
        } else if (shifted & 0x4 != 0) {
            lookup = 2;
        } else if (shifted & 0x2 != 0) {
            lookup = 1;
        } else {
            lookup = 0;
        }
        r |= lookup;
    }

    function log2(uint256 value, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = log2(value);
            return result + toUint(unsignedRoundsUp(rounding) && (uint256(1) << result) < value);
        }
    }

    function log10(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >= 10 ** 64) {
                value /= 10 ** 64;
                result += 64;
            }
            if (value >= 10 ** 32) {
                value /= 10 ** 32;
                result += 32;
            }
            if (value >= 10 ** 16) {
                value /= 10 ** 16;
                result += 16;
            }
            if (value >= 10 ** 8) {
                value /= 10 ** 8;
                result += 8;
            }
            if (value >= 10 ** 4) {
                value /= 10 ** 4;
                result += 4;
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

    function log10(uint256 value, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = log10(value);
            return result + toUint(unsignedRoundsUp(rounding) && 10 ** result < value);
        }
    }

    function log256(uint256 x) internal pure returns (uint256 r) {
        r = toUint(x > 0xffffffffffffffffffffffffffffffff) << 7;
        r |= toUint((x >> r) > 0xffffffffffffffff) << 6;
        r |= toUint((x >> r) > 0xffffffff) << 5;
        r |= toUint((x >> r) > 0xffff) << 4;
        return (r >> 3) | toUint((x >> r) > 0xff);
    }

    function log256(uint256 value, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = log256(value);
            return result + toUint(unsignedRoundsUp(rounding) && (uint256(1) << (result << 3)) < value);
        }
    }

    function unsignedRoundsUp(Rounding rounding) internal pure returns (bool) {
        return uint8(rounding) % 2 == 1;
    }
}