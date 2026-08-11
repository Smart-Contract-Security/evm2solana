// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @notice Library for converting numbers into strings and other string operations.
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/utils/LibString.sol)
/// @author Modified from Solmate (https://github.com/transmissions11/solmate/blob/main/src/utils/LibString.sol)
///
/// @dev Note:
/// For performance and bytecode compactness, most of the string operations are restricted to
/// byte strings (7-bit ASCII), except where otherwise specified.
/// Usage of byte string operations on charsets with runes spanning two or more bytes
/// can lead to undefined behavior.
library LibString {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STRUCTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Goated string storage struct that totally MOGs, no cap, fr.
    /// Uses less gas and bytecode than Solidity's native string storage. It's meta af.
    /// Packs length with the first 31 bytes if <255 bytes, so it’s mad tight.
    struct StringStorage {
        bytes32 _spacer;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CUSTOM ERRORS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The length of the output is too small to contain all the hex digits.
    error HexLengthInsufficient();

    /// @dev The length of the string is more than 32 bytes.
    error TooBigForSmallString();

    /// @dev The input string must be a 7-bit ASCII.
    error StringNot7BitASCII();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The constant returned when the `search` is not found in the string.
    uint256 internal constant NOT_FOUND = type(uint256).max;

    /// @dev Lookup for '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'.
    uint128 internal constant ALPHANUMERIC_7_BIT_ASCII = 0x7fffffe07fffffe03ff000000000000;

    /// @dev Lookup for 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'.
    uint128 internal constant LETTERS_7_BIT_ASCII = 0x7fffffe07fffffe0000000000000000;

    /// @dev Lookup for 'abcdefghijklmnopqrstuvwxyz'.
    uint128 internal constant LOWERCASE_7_BIT_ASCII = 0x7fffffe000000000000000000000000;

    /// @dev Lookup for 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.
    uint128 internal constant UPPERCASE_7_BIT_ASCII = 0x7fffffe0000000000000000;

    /// @dev Lookup for '0123456789'.
    uint128 internal constant DIGITS_7_BIT_ASCII = 0x3ff000000000000;

    /// @dev Lookup for '0123456789abcdefABCDEF'.
    uint128 internal constant HEXDIGITS_7_BIT_ASCII = 0x7e0000007e03ff000000000000;

    /// @dev Lookup for '01234567'.
    uint128 internal constant OCTDIGITS_7_BIT_ASCII = 0xff000000000000;

    /// @dev Lookup for '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ!"#$%&\'()*+,-./:;<=>?@[\\]^_`{|}~ \t\n\r\x0b\x0c'.
    uint128 internal constant PRINTABLE_7_BIT_ASCII = 0x7fffffffffffffffffffffff00003e00;

    /// @dev Lookup for '!"#$%&\'()*+,-./:;<=>?@[\\]^_`{|}~'.
    uint128 internal constant PUNCTUATION_7_BIT_ASCII = 0x78000001f8000001fc00fffe00000000;

    /// @dev Lookup for ' \t\n\r\x0b\x0c'.
    uint128 internal constant WHITESPACE_7_BIT_ASCII = 0x100003e00;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                 STRING STORAGE OPERATIONS                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Sets the value of the string storage `$` to `s`.
    function set(StringStorage storage $, string memory s) internal {
        bytes storage b = bytesStorage($);
        bytes memory bs = bytes(s);
        uint256 len = bs.length;
        for (uint256 i = 0; i < len; i++) {
            b.push(bs[i]);
        }
    }

    /// @dev Sets the value of the string storage `$` to `s`.
    function setCalldata(StringStorage storage $, string calldata s) internal {
        bytes storage b = bytesStorage($);
        bytes memory bs = bytes(s);
        uint256 len = bs.length;
        for (uint256 i = 0; i < len; i++) {
            b.push(bs[i]);
        }
    }

    /// @dev Sets the value of the string storage `$` to the empty string.
    function clear(StringStorage storage $) internal {
        delete $._spacer;
    }

    /// @dev Returns whether the value stored is `$` is the empty string "".
    function isEmpty(StringStorage storage $) internal view returns (bool) {
        return uint256($._spacer) & 0xff == uint256(0);
    }

    /// @dev Returns the length of the value stored in `$`.
    function length(StringStorage storage $) internal view returns (uint256) {
        return bytesStorage($).length;
    }

    /// @dev Returns the value stored in `$`.
    function get(StringStorage storage $) internal view returns (string memory) {
        bytes memory b = bytesStorage($);
        return string(b);
    }

    /// @dev Returns the uint8 at index `i`. If out-of-bounds, returns 0.
    function uint8At(StringStorage storage $, uint256 i) internal view returns (uint8) {
        bytes memory b = bytesStorage($);
        if (i >= b.length) return 0;
        return uint8(b[i]);
    }

    /// @dev Helper to cast `$` to a `BytesStorage`.
    function bytesStorage(StringStorage storage $)
        internal
        pure
        returns (bytes storage casted)
    {
        /// @solidity memory-safe-assembly
        assembly {
            casted.slot := $.slot
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     DECIMAL OPERATIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Returns the base 10 decimal representation of `value`.
    function toString(uint256 value) internal pure returns (string memory result) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    /// @dev Returns the base 10 decimal representation of `value`.
    function toString(int256 value) internal pure returns (string memory result) {
        if (value >= 0) return toString(uint256(value));
        uint256 absValue = uint256(-value);
        string memory absStr = toString(absValue);
        bytes memory buffer = bytes(absStr);
        bytes memory newBuffer = new bytes(buffer.length + 1);
        newBuffer[0] = '-';
        for (uint256 i = 0; i < buffer.length; i++) {
            newBuffer[i + 1] = buffer[i];
        }
        return string(newBuffer);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   HEXADECIMAL OPERATIONS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Returns the hexadecimal representation of `value`,
    /// left-padded to an input length of `byteCount` bytes.
    /// The output is prefixed with "0x" encoded using 2 hexadecimal digits per byte,
    /// giving a total length of `byteCount * 2 + 2` bytes.
    /// Reverts if `byteCount` is too small for the output to contain all the digits.
    function toHexString(uint256 value, uint256 byteCount)
        internal
        pure
        returns (string memory result)
    {
        result = toHexStringNoPrefix(value, byteCount);
        bytes memory buffer = bytes(result);
        bytes memory newBuffer = new bytes(buffer.length + 2);
        newBuffer[0] = '0';
        newBuffer[1] = 'x';
        for (uint256 i = 0; i < buffer.length; i++) {
            newBuffer[i + 2] = buffer[i];
        }
        result = string(newBuffer);
    }

    /// @dev Returns the hexadecimal representation of `value`,
    /// left-padded to an input length of `byteCount` bytes.
    /// The output is not prefixed with "0x" and is encoded using 2 hexadecimal digits per byte,
    /// giving a total length of `byteCount * 2` bytes.
    /// Reverts if `byteCount` is too small for the output to contain all the digits.
    function toHexStringNoPrefix(uint256 value, uint256 byteCount)
        internal
        pure
        returns (string memory result)
    {
        bytes memory buffer = new bytes(byteCount * 2);
        bytes memory hexChars = "0123456789abcdef";
        for (uint256 i = 0; i < byteCount; i++) {
            uint256 b = (value >> (8 * (byteCount - 1 - i))) & 0xff;
            buffer[2 * i] = hexChars[b / 16];
            buffer[2 * i + 1] = hexChars[b % 16];
        }
        result = string(buffer);
    }

    /// @dev Returns the hexadecimal representation of `value`.
    /// The output is prefixed with "0x" and encoded using 2 hexadecimal digits per byte.
    /// As address are 20 bytes long, the output will left-padded to have
    /// a length of `20 * 2 + 2` bytes.
    function toHexString(uint256 value) internal pure returns (string memory result) {
        result = toHexStringNoPrefix(value);
        bytes memory buffer = bytes(result);
        bytes memory newBuffer = new bytes(buffer.length + 2);
        newBuffer[0] = '0';
        newBuffer[1] = 'x';
        for (uint256 i = 0; i < buffer.length; i++) {
            newBuffer[i + 2] = buffer[i];
        }
        result = string(newBuffer);
    }

    /// @dev Returns the hexadecimal representation of `value`.
    /// The output is prefixed with "0x".
    /// The output excludes leading "0" from the `toHexString` output.
    /// `0x00: "0x0", 0x01: "0x1", 0x12: "0x12", 0x123: "0x123"`.
    function toMinimalHexString(uint256 value) internal pure returns (string memory result) {
        result = toHexStringNoPrefix(value);
        bytes memory buffer = bytes(result);
        uint256 start = 0;
        while (start < buffer.length && buffer[start] == '0') {
            start++;
        }
        if (start == buffer.length) {
            return "0x0";
        }
        bytes memory newBuffer = new bytes(buffer.length - start + 2);
        newBuffer[0] = '0';
        newBuffer[1] = 'x';
        for (uint256 i = start; i < buffer.length; i++) {
            newBuffer[i - start + 2] = buffer[i];
        }
        result = string(newBuffer);
    }

    /// @dev Returns the hexadecimal representation of `value`.
    /// The output excludes leading "0" from the `toHexStringNoPrefix` output.
    /// `0x00: "0", 0x01: "1", 0x12: "12", 0x123: "123"`.
    function toMinimalHexStringNoPrefix(uint256 value)
        internal
        pure
        returns (string memory result)
    {
        result = toHexStringNoPrefix(value);
        bytes memory buffer = bytes(result);
        uint256 start = 0;
        while (start < buffer.length && buffer[start] == '0') {
            start++;
        }
        if (start == buffer.length) {
            return "0";
        }
        bytes memory newBuffer = new bytes(buffer.length - start);
        for (uint256 i = start; i < buffer.length; i++) {
            newBuffer[i - start] = buffer[i];
        }
        result = string(newBuffer);
    }

    /// @dev Returns the hexadecimal representation of `value`.
    /// The output is encoded using 2 hexadecimal digits per byte.
    /// As address are 20 bytes long, the output will left-padded to have
    /// a length of `20 * 2` bytes.
    function toHexStringNoPrefix(uint256 value) internal pure returns (string memory result) {
        bytes memory buffer = new bytes(40);
        bytes memory hexChars = "0123456789abcdef";
        for (uint256 i = 0; i < 20; i++) {
            uint256 b = (value >> (8 * (19 - i))) & 0xff;
            buffer[2 * i] = hexChars[b / 16];
            buffer[2 * i + 1] = hexChars[b % 16];
        }
        result = string(buffer);
    }

    /// @dev Returns the hexadecimal representation of `value`.
    /// The output is prefixed with "0x", encoded using 2 hexadecimal digits per byte,
    /// and the alphabets are capitalized conditionally according to
    /// https://eips.ethereum.org/EIPS/eip-55
    function toHexStringChecksummed(address value) internal pure returns (string memory result) {
        result = toHexString(value);
        bytes memory buffer = bytes(result);
        // Skip "0x"
        bytes memory addrBytes = new bytes(20);
        for (uint256 i = 0; i < 20; i++) {
            addrBytes[i] = bytes1(uint8(uint160(value) >> (8 * (19 - i))));
        }
        bytes32 hash = keccak256(abi.encodePacked(buffer));
        for (uint256 i = 0; i < 20; i++) {
            uint8 b = uint8(addrBytes[i]);
            if (b >= 10 && b <= 15) {
                uint8 hashByte = uint8(hash[i >> 1]);
                if (i % 2 == 0) {
                    hashByte = hashByte >> 4;
                } else {
                    hashByte = hashByte & 0x0f;
                }
                if (hashByte >= 8) {
                    buffer[2 + 2 * i] = bytes1(b + 55); // uppercase
                } else {
                    buffer[2 + 2 * i] = bytes1(b + 87); // lowercase
                }
            }
        }
        result = string(buffer);
    }

    /// @dev Returns the hexadecimal representation of `value`.
    /// The output is prefixed with "0x" and encoded using 2 hexadecimal digits per byte.
    function toHexString(address value) internal pure returns (string memory result) {
        result = toHexStringNoPrefix(value);
        bytes memory buffer = bytes(result);
        bytes memory newBuffer = new bytes(buffer.length + 2);
        newBuffer[0] = '0';
        newBuffer[1] = 'x';
        for (uint256 i = 0; i < buffer.length; i++) {
            newBuffer[i + 2] = buffer[i];
        }
        result = string(newBuffer);
    }

    /// @dev Returns the hexadecimal representation of `value`.
    /// The output is encoded using 2 hexadecimal digits per byte.
    function toHexStringNoPrefix(address value) internal pure returns (string memory result) {
        bytes memory buffer = new bytes(40);
        bytes memory hexChars = "0123456789abcdef";
        uint160 addr = uint160(value);
        for (uint256 i = 0; i < 20; i++) {
            uint8 b = uint8(addr >> (8 * (19 - i)));
            buffer[2 * i] = hexChars[b / 16];
            buffer[2 * i + 1] = hexChars[b % 16];
        }
        result = string(buffer);
    }

    /// @dev Returns the hex encoded string from the raw bytes.
    /// The output is encoded using 2 hexadecimal digits per byte.
    function toHexString(bytes memory raw) internal pure returns (string memory result) {
        result = toHexStringNoPrefix(raw);
        bytes memory buffer = bytes(result);
        bytes memory newBuffer = new bytes(buffer.length + 2);
        newBuffer[0] = '0';
        newBuffer[1] = 'x';
        for (uint256 i = 0; i < buffer.length; i++) {
            newBuffer[i + 2] = buffer[i];
        }
        result = string(newBuffer);
    }

    /// @dev Returns the hex encoded string from the raw bytes.
    /// The output is encoded using 2 hexadecimal digits per byte.
    function toHexStringNoPrefix(bytes memory raw) internal pure returns (string memory result) {
        bytes memory buffer = new bytes(raw.length * 2);
        bytes memory hexChars = "0123456789abcdef";
        for (uint256 i = 0; i < raw.length; i++) {
            uint8 b = uint8(raw[i]);
            buffer[2 * i] = hexChars[b / 16];
            buffer[2 * i + 1] = hexChars[b % 16];
        }
        result = string(buffer);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   RUNE STRING OPERATIONS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Returns the number of UTF characters in the string.
    function runeCount(string memory s) internal pure returns (uint256 result) {
        bytes memory b = bytes(s);
        result = 0;
        uint256 i = 0;
        while (i < b.length) {
            uint8 c = uint8(b[i]);
            if (c < 0x80) {
                i += 1;
            } else if (c < 0xE0) {
                i += 2;
            } else if (c < 0xF0) {
                i += 3;
            } else {
                i += 4;
            }
            result++;
        }
    }

    /// @dev Returns if this string is a 7-bit ASCII string.
    /// (i.e. all characters codes are in [0..127])
    function is7BitASCII(string memory s) internal pure returns (bool result) {
        bytes memory b = bytes(s);
        for (uint256 i = 0; i < b.length; i++) {
            if (uint8(b[i]) > 127) {
                return false;
            }
        }
        return true;
    }

    /// @dev Returns if this string is a 7-bit ASCII string,
    /// AND all characters are in the `allowed` lookup.
    /// Note: If `s` is empty, returns true regardless of `allowed`.
    function is7BitASCII(string memory s, uint128 allowed) internal pure returns (bool result) {
        bytes memory b = bytes(s);
        for (uint256 i = 0; i < b.length; i++) {
            uint8 c = uint8(b[i]);
            if (c > 127 || (allowed & (uint128(1) << c)) == 0) {
                return false;
            }
        }
        return true;
    }

    /// @dev Converts the bytes in the 7-bit ASCII string `s` to
    /// an allowed lookup for use in `is7BitASCII(s, allowed)`.
    /// To save runtime gas, you can cache the result in an immutable variable.
    function to7BitASCIIAllowedLookup(string memory s) internal pure returns (uint128 result) {
        bytes memory b = bytes(s);
        result = 0;
        for (uint256 i = 0; i < b.length; i++) {
            uint8 c = uint8(b[i]);
            if (c > 127) {
                revert("StringNot7BitASCII");
            }
            result |= uint128(1) << c;
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   BYTE STRING OPERATIONS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    // For performance and bytecode compactness, byte string operations are restricted
    // to 7-bit ASCII strings. All offsets are byte offsets, not UTF character offsets.
    // Usage of byte string operations on charsets with runes spanning two or more bytes
    // can lead to undefined behavior.

    /// @dev Returns `subject` all occurrences of `needle` replaced with `replacement`.
    function replace(string memory subject, string memory needle, string memory replacement)
        internal
        pure
        returns (string memory)
    {
        return string(replaceBytes(bytes(subject), bytes(needle), bytes(replacement)));
    }

    /// @dev Returns the byte index of the first location of `needle` in `subject`,
    /// needleing from left to right, starting from `from`.
    /// Returns `NOT_FOUND` (i.e. `type(uint256).max`) if the `needle` is not found.
    function indexOf(string memory subject, string memory needle, uint256 from)
        internal
        pure
        returns (uint256)
    {
        return indexOfBytes(bytes(subject), bytes(needle), from);
    }

    /// @dev Returns the byte index of the first location of `needle` in `subject`,
    /// needleing from left to right.
    /// Returns `NOT_FOUND` (i.e. `type(uint256).max`) if the `needle` is not found.
    function indexOf(string memory subject, string memory needle) internal pure returns (uint256) {
        return indexOfBytes(bytes(subject), bytes(needle), 0);
    }

    /// @dev Returns the byte index of the first location of `needle` in `subject`,
    /// needleing from right to left, starting from `from`.
    /// Returns `NOT_FOUND` (i.e. `type(uint256).max`) if the `needle` is not found.
    function lastIndexOf(string memory subject, string memory needle, uint256 from)
        internal
        pure
        returns (uint256)
    {
        return lastIndexOfBytes(bytes(subject), bytes(needle), from);
    }

    /// @dev Returns the byte index of the first location of `needle` in `subject`,
    /// needleing from right to left.
    /// Returns `NOT_FOUND` (i.e. `type(uint256).max`) if the `needle` is not found.
    function lastIndexOf(string memory subject, string memory needle)
        internal
        pure
        returns (uint256)
    {
        return lastIndexOfBytes(bytes(subject), bytes(needle), type(uint256).max);
    }

    /// @dev Returns true if `needle` is found in `subject`, false otherwise.
    function contains(string memory subject, string memory needle) internal pure returns (bool) {
        return indexOfBytes(bytes(subject), bytes(needle), 0) != NOT_FOUND;
    }

    /// @dev Returns whether `subject` starts with `needle`.
    function startsWith(string memory subject, string memory needle) internal pure returns (bool) {
        bytes memory s = bytes(subject);
        bytes memory n = bytes(needle);
        if (n.length > s.length) return false;
        for (uint256 i = 0; i < n.length; i++) {
            if (s[i] != n[i]) return false;
        }
        return true;
    }

    /// @dev Returns whether `subject` ends with `needle`.
    function endsWith(string memory subject, string memory needle) internal pure returns (bool) {
        bytes memory s = bytes(subject);
        bytes memory n = bytes(needle);
        if (n.length > s.length) return false;
        uint256 offset = s.length - n.length;
        for (uint256 i = 0; i < n.length; i++) {
            if (s[offset + i] != n[i]) return false;
        }
        return true;
    }

    /// @dev Returns `subject` repeated `times`.
    function repeat(string memory subject, uint256 times) internal pure returns (string memory) {
        bytes memory s = bytes(subject);
        bytes memory buffer = new bytes(s.length * times);
        for (uint256 i = 0; i < times; i++) {
            for (uint256 j = 0; j < s.length; j++) {
                buffer[i * s.length + j] = s[j];
            }
        }
        return string(buffer);
    }

    /// @dev Returns a copy of `subject` sliced from `start` to `end` (exclusive).
    /// `start` and `end` are byte offsets.
    function slice(string memory subject, uint256 start, uint256 end)
        internal
        pure
        returns (string memory)
    {
        bytes memory s = bytes(subject);
        if (start > s.length) start = s.length;
        if (end > s.length) end = s.length;
        if (start > end) start = end;
        bytes memory buffer = new bytes(end - start);
        for (uint256 i = start; i < end; i++) {
            buffer[i - start] = s[i];
        }
        return string(buffer);
    }

    /// @dev Returns a copy of `subject` sliced from `start` to the end of the string.
    /// `start` is a byte offset.
    function slice(string memory subject, uint256 start) internal pure returns (string memory) {
        return slice(subject, start, bytes(subject).length);
    }

    /// @dev Returns all the indices of `needle` in `subject`.
    /// The indices are byte offsets.
    function indicesOf(string memory subject, string memory needle)
        internal
        pure
        returns (uint256[] memory)
    {
        bytes memory s = bytes(subject);
        bytes memory n = bytes(needle);
        uint256 count = 0;
        uint256[] memory temp = new uint256[](s.length);
        uint256 pos = 0;
        while (pos <= s.length - n.length) {
            bool found = true;
            for (uint256 j = 0; j < n.length; j++) {
                if (s[pos + j] != n[j]) {
                    found = false;
                    break;
                }
            }
            if (found) {
                temp[count] = pos;
                count++;
                pos += n.length;
            } else {
                pos++;
            }
        }
        uint256[] memory result = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = temp[i];
        }
        return result;
    }

    /// @dev Returns an arrays of strings based on the `delimiter` inside of the `subject` string.
    function split(string memory subject, string memory delimiter)
        internal
        pure
        returns (string[] memory result)
    {
        bytes memory s = bytes(subject);
        bytes memory d = bytes(delimiter);
        if (d.length == 0) {
            result = new string[](s.length);
            for (uint256 i = 0; i < s.length; i++) {
                result[i] = string(abi.encodePacked(s[i]));
            }
            return result;
        }
        uint256 count = 0;
        uint256[] memory positions = new uint256[](s.length + 1);
        uint256 pos = 0;
        positions[count++] = 0;
        while (pos <= s.length - d.length) {
            bool found = true;
            for (uint256 j = 0; j < d.length; j++) {
                if (s[pos + j] != d[j]) {
                    found = false;
                    break;
                }
            }
            if (found) {
                positions[count++] = pos + d.length;
                pos += d.length;
            } else {
                pos++;
            }
        }
        if (positions[count - 1] != s.length) {
            positions[count++] = s.length;
        }
        result = new string[](count - 1);
        for (uint256 i = 0; i < count - 1; i++) {
            uint256 start = positions[i];
            uint256 end = positions[i + 1];
            bytes memory buffer = new bytes(end - start);
            for (uint256 j = start; j < end; j++) {
                buffer[j - start] = s[j];
            }
            result[i] = string(buffer);
        }
    }

    /// @dev Returns a concatenated string of `a` and `b`.
    /// Cheaper than `string.concat()` and does not de-align the free memory pointer.
    function concat(string memory a, string memory b) internal pure returns (string memory) {
        bytes memory ba = bytes(a);
        bytes memory bb = bytes(b);
        bytes memory buffer = new bytes(ba.length + bb.length);
        for (uint256 i = 0; i < ba.length; i++) {
            buffer[i] = ba[i];
        }
        for (uint256 i = 0; i < bb.length; i++) {
            buffer[ba.length + i] = bb[i];
        }
        return string(buffer);
    }

    /// @dev Returns a copy of the string in either lowercase or UPPERCASE.
    /// WARNING! This function is only compatible with 7-bit ASCII strings.
    function toCase(string memory subject, bool toUpper)
        internal
        pure
        returns (string memory result)
    {
        bytes memory s = bytes(subject);
        bytes memory buffer = new bytes(s.length);
        for (uint256 i = 0; i < s.length; i++) {
            uint8 c = uint8(s[i]);
            if (toUpper) {
                if (c >= 97 && c <= 122) {
                    c -= 32;
                }
            } else {
                if (c >= 65 && c <= 90) {
                    c += 32;
                }
            }
            buffer[i] = bytes1(c);
        }
        result = string(buffer);
    }

    /// @dev Returns a string from a small bytes32 string.
    /// `s` must be null-terminated, or behavior will be undefined.
    function fromSmallString(bytes32 s) internal pure returns (string memory result) {
        uint256 len = 0;
        for (uint256 i = 0; i < 32; i++) {
            if (s[i] == 0) {
                len = i;
                break;
            }
        }
        bytes memory buffer = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            buffer[i] = s[i];
        }
        result = string(buffer);
    }

    /// @dev Returns the small string, with all bytes after the first null byte zeroized.
    function normalizeSmallString(bytes32 s) internal pure returns (bytes32 result) {
        result = s;
        for (uint256 i = 0; i < 32; i++) {
            if (result[i] == 0) {
                for (uint256 j = i + 1; j < 32; j++) {
                    result[j] = 0;
                }
                break;
            }
        }
    }

    /// @dev Returns the string as a normalized null-terminated small string.
    function toSmallString(string memory s) internal pure returns (bytes32 result) {
        bytes memory b = bytes(s);
        if (b.length > 31) {
            revert("TooBigForSmallString");
        }
        result = bytes32(0);
        for (uint256 i = 0; i < b.length; i++) {
            result |= bytes32(uint256(uint8(b[i]))) >> (i * 8);
        }
    }

    /// @dev Returns a lowercased copy of the string.
    /// WARNING! This function is only compatible with 7-bit ASCII strings.
    function lower(string memory subject) internal pure returns (string memory result) {
        result = toCase(subject, false);
    }

    /// @dev Returns an UPPERCASED copy of the string.
    /// WARNING! This function is only compatible with 7-bit ASCII strings.
    function upper(string memory subject) internal pure returns (string memory result) {
        result = toCase(subject, true);
    }

    /// @dev Escapes the string to be used within HTML tags.
    function escapeHTML(string memory s) internal pure returns (string memory result) {
        bytes memory input = bytes(s);
        bytes memory buffer = new bytes(input.length * 6); // max expansion
        uint256 pos = 0;
        for (uint256 i = 0; i < input.length; i++) {
            uint8 c = uint8(input[i]);
            if (c == 34) { // "
                buffer[pos++] = '&';
                buffer[pos++] = 'q';
                buffer[pos++] = 'u';
                buffer[pos++] = 'o';
                buffer[pos++] = 't';
                buffer[pos++] = ';';
            } else if (c == 38) { // &
                buffer[pos++] = '&';
                buffer[pos++] = 'a';
                buffer[pos++] = 'm';
                buffer[pos++] = 'p';
                buffer[pos++] = ';';
            } else if (c == 39) { // '
                buffer[pos++] = '&';
                buffer[pos++] = '#';
                buffer[pos++] = '3';
                buffer[pos++] = '9';
                buffer[pos++] = ';';
            } else if (c == 60) { // <
                buffer[pos++] = '&';
                buffer[pos++] = 'l';
                buffer[pos++] = 't';
                buffer[pos++] = ';';
            } else if (c == 62) { // >
                buffer[pos++] = '&';
                buffer[pos++] = 'g';
                buffer[pos++] = 't';
                buffer[pos++] = ';';
            } else {
                buffer[pos++] = bytes1(c);
            }
        }
        bytes memory finalBuffer = new bytes(pos);
        for (uint256 i = 0; i < pos; i++) {
            finalBuffer[i] = buffer[i];
        }
        result = string(finalBuffer);
    }

    /// @dev Escapes the string to be used within double-quotes in a JSON.
    /// If `addDoubleQuotes` is true, the result will be enclosed in double-quotes.
    function escapeJSON(string memory s, bool addDoubleQuotes)
        internal
        pure
        returns (string memory result)
    {
        bytes memory input = bytes(s);
        bytes memory buffer = new bytes(input.length * 6 + 2); // max expansion + quotes
        uint256 pos = 0;
        if (addDoubleQuotes) {
            buffer[pos++] = '"';
        }
        for (uint256 i = 0; i < input.length; i++) {
            uint8 c = uint8(input[i]);
            if (c == 34 || c == 92) { // " or \
                buffer[pos++] = '\\';
                buffer[pos++] = bytes1(c);
            } else if (c >= 32) {
                buffer[pos++] = bytes1(c);
            } else if (c == 8) {
                buffer[pos++] = '\\';
                buffer[pos++] = 'b';
            } else if (c == 9) {
                buffer[pos++] = '\\';
                buffer[pos++] = 't';
            } else if (c == 10) {
                buffer[pos++] = '\\';
                buffer[pos++] = 'n';
            } else if (c == 12) {
                buffer[pos++] = '\\';
                buffer[pos++] = 'f';
            } else if (c == 13) {
                buffer[pos++] = '\\';
                buffer[pos++] = 'r';
            } else {
                buffer[pos++] = '\\';
                buffer[pos++] = 'u';
                buffer[pos++] = '0';
                buffer[pos++] = '0';
                buffer[pos++] = bytes1(uint8(48 + c / 16));
                buffer[pos++] = bytes1(uint8(48 + c % 16));
            }
        }
        if (addDoubleQuotes) {
            buffer[pos++] = '"';
        }
        bytes memory finalBuffer = new bytes(pos);
        for (uint256 i = 0; i < pos; i++) {
            finalBuffer[i] = buffer[i];
        }
        result = string(finalBuffer);
    }

    /// @dev Escapes the string to be used within double-quotes in a JSON.
    function escapeJSON(string memory s) internal pure returns (string memory result) {
        result = escapeJSON(s, false);
    }

    /// @dev Encodes `s` so that it can be safely used in a URI,
    /// just like `encodeURIComponent` in JavaScript.
    /// See: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/encodeURIComponent
    /// See: https://datatracker.ietf.org/doc/html/rfc2396
    /// See: https://datatracker.ietf.org/doc/html/rfc3986
    function encodeURIComponent(string memory s) internal pure returns (string memory result) {
        bytes memory input = bytes(s);
        bytes memory buffer = new bytes(input.length * 3); // max expansion
        uint256 pos = 0;
        bytes memory hexChars = "0123456789ABCDEF";
        for (uint256 i = 0; i < input.length; i++) {
            uint8 c = uint8(input[i]);
            if ((c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) ||
                c == 45 || c == 95 || c == 46 || c == 33 || c == 126 || c == 42 || c == 39 || c == 40 || c == 41) {
                buffer[pos++] = bytes1(c);
            } else {
                buffer[pos++] = '%';
                buffer[pos++] = hexChars[c / 16];
                buffer[pos++] = hexChars[c % 16];
            }
        }
        bytes memory finalBuffer = new bytes(pos);
        for (uint256 i = 0; i < pos; i++) {
            finalBuffer[i] = buffer[i];
        }
        result = string(finalBuffer);
    }

    /// @dev Returns whether `a` equals `b`.
    function eq(string memory a, string memory b) internal pure returns (bool result) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    /// @dev Returns whether `a` equals `b`, where `b` is a null-terminated small string.
    function eqs(string memory a, bytes32 b) internal pure returns (bool result) {
        bytes memory ba = bytes(a);
        uint256 len = 0;
        for (uint256 i = 0; i < 32; i++) {
            if (b[i] == 0) {
                len = i;
                break;
            }
        }
        if (ba.length != len) return false;
        for (uint256 i = 0; i < len; i++) {
            if (ba[i] != b[i]) return false;
        }
        return true;
    }

    /// @dev Returns 0 if `a == b`, -1 if `a < b`, +1 if `a > b`.
    /// If `a` == b[:a.length]`, and `a.length < b.length`, returns -1.
    function cmp(string memory a, string memory b) internal pure returns (int256) {
        return cmpBytes(bytes(a), bytes(b));
    }

    /// @dev Packs a single string with its length into a single word.
    /// Returns `bytes32(0)` if the length is zero or greater than 31.
    function packOne(string memory a) internal pure returns (bytes32 result) {
        bytes memory ba = bytes(a);
        if (ba.length == 0 || ba.length > 31) return bytes32(0);
        result = bytes32(0);
        for (uint256 i = 0; i < ba.length; i++) {
            result |= bytes32(uint256(uint8(ba[i]))) >> (i * 8);
        }
        result |= bytes32(uint256(ba.length) << 248);
    }

    /// @dev Unpacks a string packed using {packOne}.
    /// Returns the empty string if `packed` is `bytes32(0)`.
    /// If `packed` is not an output of {packOne}, the output behavior is undefined.
    function unpackOne(bytes32 packed) internal pure returns (string memory result) {
        if (packed == bytes32(0)) return "";
        uint256 len = uint256(packed >> 248);
        bytes memory buffer = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            buffer[i] = packed[i];
        }
        result = string(buffer);
    }

    /// @dev Packs two strings with their lengths into a single word.
    /// Returns `bytes32(0)` if combined length is zero or greater than 30.
    function packTwo(string memory a, string memory b) internal pure returns (bytes32 result) {
        bytes memory ba = bytes(a);
        bytes memory bb = bytes(b);
        uint256 totalLen = ba.length + bb.length;
        if (totalLen == 0 || totalLen > 30) return bytes32(0);
        result = bytes32(0);
        for (uint256 i = 0; i < ba.length; i++) {
            result |= bytes32(uint256(uint8(ba[i]))) >> (i * 8);
        }
        for (uint256 i = 0; i < bb.length; i++) {
            result |= bytes32(uint256(uint8(bb[i]))) >> ((ba.length + i) * 8);
        }
        result |= bytes32(uint256(ba.length) << 248) | bytes32(uint256(bb.length) << 240);
    }

    /// @dev Unpacks strings packed using {packTwo}.
    /// Returns the empty strings if `packed` is `bytes32(0)`.
    /// If `packed` is not an output of {packTwo}, the output behavior is undefined.
    function unpackTwo(bytes32 packed)
        internal
        pure
        returns (string memory resultA, string memory resultB)
    {
        if (packed == bytes32(0)) return ("", "");
        uint256 lenA = uint256(packed >> 248);
        uint256 lenB = uint256((packed >> 240) & 0xff);
        bytes memory bufferA = new bytes(lenA);
        bytes memory bufferB = new bytes(lenB);
        for (uint256 i = 0; i < lenA; i++) {
            bufferA[i] = packed[i];
        }
        for (uint256 i = 0; i < lenB; i++) {
            bufferB[i] = packed[lenA + i];
        }
        resultA = string(bufferA);
        resultB = string(bufferB);
    }

    /// @dev Directly returns `a` without copying.
    function directReturn(string memory a) internal pure {
        // In Solana, we cannot use return opcode, so this is a no-op
        // The caller should handle the return value
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*              PRIVATE BYTE HELPERS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function replaceBytes(bytes memory subject, bytes memory needle, bytes memory replacement)
        private
        pure
        returns (bytes memory)
    {
        if (needle.length == 0) return subject;
        uint256 count = 0;
        uint256 pos = 0;
        while (pos <= subject.length - needle.length) {
            bool found = true;
            for (uint256 j = 0; j < needle.length; j++) {
                if (subject[pos + j] != needle[j]) {
                    found = false;
                    break;
                }
            }
            if (found) {
                count++;
                pos += needle.length;
            } else {
                pos++;
            }
        }
        bytes memory buffer = new bytes(subject.length + count * (replacement.length - needle.length));
        uint256 writePos = 0;
        pos = 0;
        while (pos < subject.length) {
            bool found = pos <= subject.length - needle.length;
            if (found) {
                for (uint256 j = 0; j < needle.length; j++) {
                    if (subject[pos + j] != needle[j]) {
                        found = false;
                        break;
                    }
                }
            }
            if (found) {
                for (uint256 j = 0; j < replacement.length; j++) {
                    buffer[writePos++] = replacement[j];
                }
                pos += needle.length;
            } else {
                buffer[writePos++] = subject[pos++];
            }
        }
        return buffer;
    }

    function indexOfBytes(bytes memory subject, bytes memory needle, uint256 from)
        private
        pure
        returns (uint256)
    {
        if (needle.length == 0) return from <= subject.length ? from : NOT_FOUND;
        if (from > subject.length) return NOT_FOUND;
        for (uint256 i = from; i <= subject.length - needle.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < needle.length; j++) {
                if (subject[i + j] != needle[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return i;
        }
        return NOT_FOUND;
    }

    function lastIndexOfBytes(bytes memory subject, bytes memory needle, uint256 from)
        private
        pure
        returns (uint256)
    {
        if (needle.length == 0) return from <= subject.length ? from : subject.length;
        if (subject.length < needle.length) return NOT_FOUND;
        uint256 start = from;
        if (start > subject.length - needle.length) {
            start = subject.length - needle.length;
        }
        for (uint256 i = start; ; i--) {
            bool found = true;
            for (uint256 j = 0; j < needle.length; j++) {
                if (subject[i + j] != needle[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return i;
            if (i == 0) break;
        }
        return NOT_FOUND;
    }

    function cmpBytes(bytes memory a, bytes memory b) private pure returns (int256) {
        uint256 minLen = a.length < b.length ? a.length : b.length;
        for (uint256 i = 0; i < minLen; i++) {
            if (a[i] < b[i]) return -1;
            if (a[i] > b[i]) return 1;
        }
        if (a.length < b.length) return -1;
        if (a.length > b.length) return 1;
        return 0;
    }
}