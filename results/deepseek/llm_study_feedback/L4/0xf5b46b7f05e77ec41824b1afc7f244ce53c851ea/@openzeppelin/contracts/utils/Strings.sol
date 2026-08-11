// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library Strings {
    bytes16 private constant HEX_DIGITS = "0123456789abcdef";
    uint8 private constant ADDRESS_LENGTH = 20;
    uint256 private constant SPECIAL_CHARS_LOOKUP =
        0xffffffff | // first 32 bits corresponding to the control characters (U+0000 to U+001F)
            (1 << 0x22) | // double quote
            (1 << 0x5c); // backslash

    function log10(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        if (value >= 10**64) {
            value /= 10**64;
            result += 64;
        }
        if (value >= 10**32) {
            value /= 10**32;
            result += 32;
        }
        if (value >= 10**16) {
            value /= 10**16;
            result += 16;
        }
        if (value >= 10**8) {
            value /= 10**8;
            result += 8;
        }
        if (value >= 10**4) {
            value /= 10**4;
            result += 4;
        }
        if (value >= 10**2) {
            value /= 10**2;
            result += 2;
        }
        if (value >= 10**1) {
            result += 1;
        }
        return result;
    }

    function log256(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        if (value >= 1 << 128) {
            value >>= 128;
            result += 16;
        }
        if (value >= 1 << 64) {
            value >>= 64;
            result += 8;
        }
        if (value >= 1 << 32) {
            value >>= 32;
            result += 4;
        }
        if (value >= 1 << 16) {
            value >>= 16;
            result += 2;
        }
        if (value >= 1 << 8) {
            result += 1;
        }
        return result;
    }

    function abs(int256 value) internal pure returns (uint256) {
        return uint256(value < 0 ? -value : value);
    }

    function toUint(bool b) internal pure returns (uint256) {
        return b ? 1 : 0;
    }

    function toString(uint256 value) internal pure returns (string memory) {
        unchecked {
            uint256 length = log10(value) + 1;
            string memory buffer = new string(length);
            bytes memory bufferBytes = bytes(buffer);
            uint256 ptr = length;
            while (true) {
                ptr--;
                bufferBytes[ptr] = HEX_DIGITS[value % 10];
                value /= 10;
                if (value == 0) break;
            }
            return buffer;
        }
    }

    function toStringSigned(int256 value) internal pure returns (string memory) {
        if (value < 0) {
            return string.concat("-", toString(abs(value)));
        } else {
            return string.concat("", toString(abs(value)));
        }
    }

    function toHexString(uint256 value) internal pure returns (string memory) {
        unchecked {
            return toHexString(value, log256(value) + 1);
        }
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
            // revert with custom errors not supported on Solana, using string revert
            revert("StringsInsufficientHexLength");
        }
        return string(buffer);
    }

    function toHexString(address addr) internal pure returns (string memory) {
        return toHexString(uint256(uint160(addr)), ADDRESS_LENGTH);
    }

    function toChecksumHexString(address addr) internal pure returns (string memory) {
        bytes memory buffer = bytes(toHexString(addr));

        bytes32 hash = keccak256(abi.encodePacked(buffer));

        for (uint256 i = 41; i > 1; --i) {
            uint8 nibble = uint8(hash[(i - 2) >> 1]);
            if ((i & 1) == 0) {
                nibble >>= 4;
            } else {
                nibble &= 0xf;
            }
            if (nibble > 7 && uint8(buffer[i]) > 96) {
                buffer[i] ^= 0x20;
            }
        }
        return string(buffer);
    }

    function toHexString(bytes memory input) internal pure returns (string memory) {
        unchecked {
            bytes memory buffer = new bytes(2 * input.length + 2);
            buffer[0] = "0";
            buffer[1] = "x";
            for (uint256 i = 0; i < input.length; ++i) {
                uint8 v = uint8(input[i]);
                buffer[2 * i + 2] = HEX_DIGITS[v >> 4];
                buffer[2 * i + 3] = HEX_DIGITS[v & 0xf];
            }
            return string(buffer);
        }
    }

    function equal(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }

    function parseUint(string memory input) internal pure returns (uint256) {
        return parseUint(input, 0, bytes(input).length);
    }

    function parseUint(string memory input, uint256 begin, uint256 end) internal pure returns (uint256) {
        (bool success, uint256 value) = tryParseUint(input, begin, end);
        if (!success) revert("StringsInvalidChar");
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
        if (!success) revert("StringsInvalidChar");
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
        uint256 offset = toUint(positiveSign || negativeSign);

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
        if (!success) revert("StringsInvalidChar");
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
        uint256 offset = toUint(hasPrefix) * 2;

        uint256 result = 0;
        for (uint256 i = begin + offset; i < end; ++i) {
            uint8 chr = _tryParseChr(buffer[i]);
            if (chr > 15) return (false, 0);
            result *= 16;
            unchecked {
                result += chr;
            }
        }
        return (true, result);
    }

    function parseAddress(string memory input) internal pure returns (address) {
        return parseAddress(input, 0, bytes(input).length);
    }

    function parseAddress(string memory input, uint256 begin, uint256 end) internal pure returns (address) {
        (bool success, address value) = tryParseAddress(input, begin, end);
        if (!success) revert("StringsInvalidAddressFormat");
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

        bytes memory inputBytes = bytes(input);
        bool hasPrefix = (end > begin + 1) && (inputBytes[begin] == "0") && (inputBytes[begin + 1] == "x");
        uint256 expectedLength = 40 + toUint(hasPrefix) * 2;

        if (end - begin == expectedLength) {
            (bool s, uint256 v) = _tryParseHexUintUncheckedBounds(input, begin, end);
            return (s, address(uint160(v)));
        } else {
            return (false, address(0));
        }
    }

    function _tryParseChr(bytes1 chr) private pure returns (uint8) {
        uint8 value = uint8(chr);

        unchecked {
            if (value > 47 && value < 58) value -= 48;
            else if (value > 96 && value < 103) value -= 87;
            else if (value > 64 && value < 71) value -= 55;
            else return type(uint8).max;
        }

        return value;
    }

    function escapeJSON(string memory input) internal pure returns (string memory) {
        bytes memory buffer = bytes(input);

        bytes memory output = new bytes(0);
        uint256 outputLength = 0;

        for (uint256 i = 0; i < buffer.length; ++i) {
            uint8 char = uint8(buffer[i]);
            if (((SPECIAL_CHARS_LOOKUP & (1 << char)) != 0)) {
                output = _appendByte(output, outputLength++, "\\");
                if (char == 0x08) output = _appendByte(output, outputLength++, "b");
                else if (char == 0x09) output = _appendByte(output, outputLength++, "t");
                else if (char == 0x0a) output = _appendByte(output, outputLength++, "n");
                else if (char == 0x0c) output = _appendByte(output, outputLength++, "f");
                else if (char == 0x0d) output = _appendByte(output, outputLength++, "r");
                else if (char == 0x5c) output = _appendByte(output, outputLength++, "\\");
                else if (char == 0x22) {
                    output = _appendByte(output, outputLength++, '"');
                } else {
                    output = _appendByte(output, outputLength++, "u");
                    output = _appendByte(output, outputLength++, "0");
                    output = _appendByte(output, outputLength++, "0");
                    output = _appendByte(output, outputLength++, HEX_DIGITS[char >> 4]);
                    output = _appendByte(output, outputLength++, HEX_DIGITS[char & 0x0f]);
                }
            } else {
                output = _appendByte(output, outputLength++, bytes1(char));
            }
        }

        return string(output);
    }

    function _appendByte(bytes memory buffer, uint256 index, bytes1 value) private pure returns (bytes memory) {
        if (index >= buffer.length) {
            bytes memory newBuffer = new bytes(index + 1);
            for (uint256 i = 0; i < buffer.length; i++) {
                newBuffer[i] = buffer[i];
            }
            newBuffer[index] = value;
            return newBuffer;
        } else {
            buffer[index] = value;
            return buffer;
        }
    }
}