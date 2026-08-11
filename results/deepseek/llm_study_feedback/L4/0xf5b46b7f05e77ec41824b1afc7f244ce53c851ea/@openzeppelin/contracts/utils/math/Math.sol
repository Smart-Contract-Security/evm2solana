// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.6.0) (utils/math/Math.sol)

pragma solidity ^0.8.20;

library Math {
    enum Rounding {
        Floor,
        Ceil,
        Trunc,
        Expand
    }

    // Panic codes
    uint256 constant PANIC_DIVISION_BY_ZERO = 0x12;
    uint256 constant PANIC_UNDER_OVERFLOW = 0x11;

    function toUint(bool b) internal pure returns (uint256) {
        unchecked {
            return b ? 1 : 0;
        }
    }

    function add512(uint256 a, uint256 b) internal pure returns (uint256 high, uint256 low) {
        low = a + b;
        high = low < a ? 1 : 0;
    }

    function mul512(uint256 a, uint256 b) internal pure returns (uint256 high, uint256 low) {
        uint256 mm = mulmod(a, b, type(uint256).max);
        low = a * b;
        high = mm - low;
        if (mm < low) {
            high -= 1;
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
            success = (a == 0) || (c / a == b);
            result = c * toUint(success);
        }
    }

    function tryDiv(uint256 a, uint256 b) internal pure returns (bool success, uint256 result) {
        unchecked {
            success = b > 0;
            result = a / b;
        }
    }

    function tryMod(uint256 a, uint256 b) internal pure returns (bool success, uint256 result) {
        unchecked {
            success = b > 0;
            result = a % b;
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
            panic(PANIC_DIVISION_BY_ZERO);
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
                panic(ternary(denominator == 0, PANIC_DIVISION_BY_ZERO, PANIC_UNDER_OVERFLOW));
            }

            uint256 remainder = mulmod(x, y, denominator);

            if (remainder > low) {
                high -= 1;
            }
            low -= remainder;

            uint256 twos = denominator & (0 - denominator);
            denominator /= twos;
            low /= twos;
            twos = (type(uint256).max / twos + 1);

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
            if (high >= 1 << n) {
                panic(PANIC_UNDER_OVERFLOW);
            }
            return (high << (256 - n)) | (low >> n);
        }
    }

    function mulShr(uint256 x, uint256 y, uint8 n, Rounding rounding) internal pure returns (uint256) {
        return mulShr(x, y, n) + toUint(unsignedRoundsUp(rounding) && mulmod(x, y, 1 << n) > 0);
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
            panic(PANIC_DIVISION_BY_ZERO);
        }
        return result;
    }

    function tryModExp(uint256 b, uint256 e, uint256 m) internal view returns (bool success, uint256 result) {
        if (m == 0) return (false, 0);
        // Solang does not support the MODEXP precompile (0x05) on Solana.
        // We implement a fallback using exponentiation by squaring.
        success = true;
        result = 1;
        b = b % m;
        while (e > 0) {
            if (e & 1 == 1) {
                result = mulmod(result, b, m);
            }
            e >>= 1;
            b = mulmod(b, b, m);
        }
    }

    function modExp(bytes memory b, bytes memory e, bytes memory m) internal view returns (bytes memory) {
        (bool success, bytes memory result) = tryModExp(b, e, m);
        if (!success) {
            panic(PANIC_DIVISION_BY_ZERO);
        }
        return result;
    }

    function tryModExp(
        bytes memory b,
        bytes memory e,
        bytes memory m
    ) internal view returns (bool success, bytes memory result) {
        if (_zeroBytes(m)) return (false, new bytes(0));

        uint256 bVal = _bytesToUint(b);
        uint256 eVal = _bytesToUint(e);
        uint256 mVal = _bytesToUint(m);

        (bool ok, uint256 res) = tryModExp(bVal, eVal, mVal);
        if (!ok) return (false, new bytes(0));

        result = _uintToBytes(res);
        success = true;
    }

    function _bytesToUint(bytes memory b) private pure returns (uint256 val) {
        uint256 len = b.length;
        require(len <= 32, "bytes too long");
        for (uint256 i = 0; i < len; i++) {
            val = (val << 8) | uint8(b[i]);
        }
    }

    function _uintToBytes(uint256 x) private pure returns (bytes memory b) {
        b = new bytes(32);
        for (uint256 i = 0; i < 32; i++) {
            b[31 - i] = bytes1(uint8(x & 0xff));
            x >>= 8;
        }
    }

    function _zeroBytes(bytes memory buffer) private pure returns (bool) {
        uint256 chunk;
        for (uint256 i = 0; i < buffer.length; i += 0x20) {
            chunk = 0;
            uint256 end = i + 0x20;
            if (end > buffer.length) {
                end = buffer.length;
            }
            for (uint256 j = i; j < end; j++) {
                chunk = (chunk << 8) | uint8(buffer[j]);
            }
            if (chunk != 0) {
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

            if (aa >= (1 << 128)) {
                aa >>= 128;
                xn <<= 64;
            }
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

        uint8[16] memory table = [
            0, 0, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3, 3, 3
        ];
        r |= table[(x >> r) & 0xf];
    }

    function log2(uint256 value, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = log2(value);
            return result + toUint(unsignedRoundsUp(rounding) && 1 << result < value);
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
            return result + toUint(unsignedRoundsUp(rounding) && 1 << (result << 3) < value);
        }
    }

    function unsignedRoundsUp(Rounding rounding) internal pure returns (bool) {
        return uint8(rounding) % 2 == 1;
    }

    function clz(uint256 x) internal pure returns (uint256) {
        return ternary(x == 0, 256, 255 - log2(x));
    }

    function panic(uint256 code) internal pure {
        revert();
    }
}