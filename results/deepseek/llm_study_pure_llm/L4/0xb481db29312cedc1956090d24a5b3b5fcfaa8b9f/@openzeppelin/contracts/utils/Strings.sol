// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library Strings {
    bytes16 private constant HEX_DIGITS = "0123456789abcdef";
    uint8 private constant ADDRESS_LENGTH = 20;
    uint256 private constant SPECIAL_CHARS_LOOKUP =
        (1 << 0x08) |
        (1 << 0x09) |
        (1 << 0x0a) |
        (1 << 0x0c) |
        (1 << 0x0d) |
        (1 << 0x22) |
        (1 << 0x5c);

    error StringsInsufficientHexLength(uint256 value, uint256 length);
    error StringsInvalidChar();
    error StringsInvalidAddressFormat();

    function toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 length;
        while (temp != 0) {
            length++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(length);
        while (value != 0) {
            length--;
            buffer[length] = bytes1(uint8(48 + (value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function toStringSigned(int256 value) internal pure returns (string memory) {
        if (value < 0) {
            return string(abi.encodePacked("-", toString(uint256(-value))));
        }
        return toString(uint256(value));
    }

    function toHexString(uint256 value) internal pure returns (string memory) {
        return toHexString(value, log256(value) + 1);
    }

    function toHexString(uint256 value, uint256 length) internal pure returns (string memory) {
        uint256 localValue = value;
        bytes memory buffer = new bytes(2 * length + 2);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint256 i = 2 * length + 1; i > 1; --i) {
            buffer[i] = HEX_DIGITS[localValue & 0xf];
            localValue >>= 4;
        }
        if (localValue != 0) {
            revert StringsInsufficientHexLength(value, length);
        }
        return string(buffer);
    }

    function toHexString(address addr) internal pure returns (string memory) {
        return toHexString(uint256(uint160(addr)), ADDRESS_LENGTH);
    }

    function toChecksumHexString(address addr) internal pure returns (string memory) {
        bytes memory buffer = bytes(toHexString(addr));
        uint256 hashValue = uint256(keccak256(abi.encodePacked(buffer))) >> 96;
        for (uint256 i = 41; i > 1; --i) {
            if (hashValue & 0xf > 7 && uint8(buffer[i]) > 96) {
                buffer[i] ^= 0x20;
            }
            hashValue >>= 4;
        }
        return string(buffer);
    }

    function equal(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    function parseUint(string memory input) internal pure returns (uint256) {
        return parseUint(input, 0, bytes(input).length);
    }

    function parseUint(string memory input, uint256 begin, uint256 end) internal pure returns (uint256) {
        (bool success, uint256 value) = tryParseUint(input, begin, end);
        if (!success) revert StringsInvalidChar();
        return value;
    }

    function tryParseUint(string memory input) internal pure returns (bool success, uint256 value) {
        return _tryParseUintUncheckedBounds(input, 0, bytes(input).length);
    }

    function tryParseUint(
        string memory input,
        uint256 begin,
        uint256 end
    ) internal pure returns (bool success, uint256 value) {
        if (end > bytes(input).length || begin > end) return (false, 0);
        return _tryParseUintUncheckedBounds(input, begin, end);
    }

    function _tryParseUintUncheckedBounds(
        string memory input,
        uint256 begin,
        uint256 end
    ) private pure returns (bool success, uint256 value) {
        bytes memory buffer = bytes(input);
        uint256 result = 0;
        for (uint256 i = begin; i < end; ++i) {
            uint8 chr = _tryParseChr(buffer[i]);
            if (chr > 9) return (false, 0);
            result *= 10;
            result += chr;
        }
        return (true, result);
    }

    function parseInt(string memory input) internal pure returns (int256) {
        return parseInt(input, 0, bytes(input).length);
    }

    function parseInt(string memory input, uint256 begin, uint256 end) internal pure returns (int256) {
        (bool success, int256 value) = tryParseInt(input, begin, end);
        if (!success) revert StringsInvalidChar();
        return value;
    }

    function tryParseInt(string memory input) internal pure returns (bool success, int256 value) {
        return _tryParseIntUncheckedBounds(input, 0, bytes(input).length);
    }

    uint256 private constant ABS_MIN_INT256 = 2 ** 255;

    function tryParseInt(
        string memory input,
        uint256 begin,
        uint256 end
    ) internal pure returns (bool success, int256 value) {
        if (end > bytes(input).length || begin > end) return (false, 0);
        return _tryParseIntUncheckedBounds(input, begin, end);
    }

    function _tryParseIntUncheckedBounds(
        string memory input,
        uint256 begin,
        uint256 end
    ) private pure returns (bool success, int256 value) {
        bytes memory buffer = bytes(input);
        bytes1 sign = begin == end ? bytes1(0) : buffer[begin];
        bool positiveSign = sign == bytes1("+");
        bool negativeSign = sign == bytes1("-");
        uint256 offset = (positiveSign || negativeSign) ? 1 : 0;

        (bool absSuccess, uint256 absValue) = tryParseUint(input, begin + offset, end);

        if (absSuccess && absValue < ABS_MIN_INT256) {
            return (true, negativeSign ? -int256(absValue) : int256(absValue));
        } else if (absSuccess && negativeSign && absValue == ABS_MIN_INT256) {
            return (true, type(int256).min);
        } else return (false, 0);
    }

    function parseHexUint(string memory input) internal pure returns (uint256) {
        return parseHexUint(input, 0, bytes(input).length);
    }

    function parseHexUint(string memory input, uint256 begin, uint256 end) internal pure returns (uint256) {
        (bool success, uint256 value) = tryParseHexUint(input, begin, end);
        if (!success) revert StringsInvalidChar();
        return value;
    }

    function tryParseHexUint(string memory input) internal pure returns (bool success, uint256 value) {
        return _tryParseHexUintUncheckedBounds(input, 0, bytes(input).length);
    }

    function tryParseHexUint(
        string memory input,
        uint256 begin,
        uint256 end
    ) internal pure returns (bool success, uint256 value) {
        if (end > bytes(input).length || begin > end) return (false, 0);
        return _tryParseHexUintUncheckedBounds(input, begin, end);
    }

    function _tryParseHexUintUncheckedBounds(
        string memory input,
        uint256 begin,
        uint256 end
    ) private pure returns (bool success, uint256 value) {
        bytes memory buffer = bytes(input);
        bool hasPrefix = (end > begin + 1) && (buffer[begin] == "0") && (buffer[begin + 1] == "x");
        uint256 offset = hasPrefix ? 2 : 0;

        uint256 result = 0;
        for (uint256 i = begin + offset; i < end; ++i) {
            uint8 chr = _tryParseChr(buffer[i]);
            if (chr > 15) return (false, 0);
            result *= 16;
            result += chr;
        }
        return (true, result);
    }

    function parseAddress(string memory input) internal pure returns (address) {
        return parseAddress(input, 0, bytes(input).length);
    }

    function parseAddress(string memory input, uint256 begin, uint256 end) internal pure returns (address) {
        (bool success, address value) = tryParseAddress(input, begin, end);
        if (!success) revert StringsInvalidAddressFormat();
        return value;
    }

    function tryParseAddress(string memory input) internal pure returns (bool success, address value) {
        return tryParseAddress(input, 0, bytes(input).length);
    }

    function tryParseAddress(
        string memory input,
        uint256 begin,
        uint256 end
    ) internal pure returns (bool success, address value) {
        if (end > bytes(input).length || begin > end) return (false, address(0));

        bytes memory buffer = bytes(input);
        bool hasPrefix = (end > begin + 1) && (buffer[begin] == "0") && (buffer[begin + 1] == "x");
        uint256 expectedLength = 40 + (hasPrefix ? 2 : 0);

        if (end - begin == expectedLength) {
            (bool s, uint256 v) = _tryParseHexUintUncheckedBounds(input, begin, end);
            return (s, address(uint160(v)));
        } else {
            return (false, address(0));
        }
    }

    function _tryParseChr(bytes1 chr) private pure returns (uint8) {
        uint8 value = uint8(chr);
        if (value >= 48 && value <= 57) {
            return value - 48;
        } else if (value >= 97 && value <= 102) {
            return value - 87;
        } else if (value >= 65 && value <= 70) {
            return value - 55;
        } else {
            return type(uint8).max;
        }
    }

    function escapeJSON(string memory input) internal pure returns (string memory) {
        bytes memory buffer = bytes(input);
        bytes memory output = new bytes(2 * buffer.length);
        uint256 outputLength = 0;

        for (uint256 i = 0; i < buffer.length; ++i) {
            bytes1 char = buffer[i];
            if (((SPECIAL_CHARS_LOOKUP & (1 << uint8(char))) != 0)) {
                output[outputLength++] = "\\";
                if (char == 0x08) output[outputLength++] = "b";
                else if (char == 0x09) output[outputLength++] = "t";
                else if (char == 0x0a) output[outputLength++] = "n";
                else if (char == 0x0c) output[outputLength++] = "f";
                else if (char == 0x0d) output[outputLength++] = "r";
                else if (char == 0x5c) output[outputLength++] = "\\";
                else if (char == 0x22) {
                    output[outputLength++] = '"';
                }
            } else {
                output[outputLength++] = char;
            }
        }

        bytes memory result = new bytes(outputLength);
        for (uint256 j = 0; j < outputLength; j++) {
            result[j] = output[j];
        }
        return string(result);
    }

    function log256(uint256 value) private pure returns (uint256) {
        uint256 result;
        if (value >= 0x100000000000000000000000000000000) { value >>= 128; result += 16; }
        if (value >= 0x10000000000000000) { value >>= 64; result += 8; }
        if (value >= 0x100000000) { value >>= 32; result += 4; }
        if (value >= 0x10000) { value >>= 16; result += 2; }
        if (value >= 0x100) { value >>= 8; result += 1; }
        if (value >= 0x10) { result += 1; }
        return result;
    }
}