// SPDX-License-Identifier: MIT

library LibString {
    struct StringStorage {
        bytes32 _spacer;
    }

    uint256 internal constant NOT_FOUND = type(uint256).max;

    uint128 internal constant ALPHANUMERIC_7_BIT_ASCII = 0x7fffffe07fffffe03ff000000000000;

    uint128 internal constant LETTERS_7_BIT_ASCII = 0x7fffffe07fffffe0000000000000000;

    uint128 internal constant LOWERCASE_7_BIT_ASCII = 0x7fffffe000000000000000000000000;

    uint128 internal constant UPPERCASE_7_BIT_ASCII = 0x7fffffe0000000000000000;

    uint128 internal constant DIGITS_7_BIT_ASCII = 0x3ff000000000000;

    uint128 internal constant HEXDIGITS_7_BIT_ASCII = 0x7e0000007e03ff000000000000;

    uint128 internal constant OCTDIGITS_7_BIT_ASCII = 0xff000000000000;

    uint128 internal constant PRINTABLE_7_BIT_ASCII = 0x7fffffffffffffffffffffff00003e00;

    uint128 internal constant PUNCTUATION_7_BIT_ASCII = 0x78000001f8000001fc00fffe00000000;

    uint128 internal constant WHITESPACE_7_BIT_ASCII = 0x100003e00;

    function set(StringStorage storage $, string memory s) internal {
        bytesStorage($)._data = bytes(s);
    }

    function setCalldata(StringStorage storage $, string calldata s) internal {
        bytesStorage($)._data = bytes(s);
    }

    function clear(StringStorage storage $) internal {
        delete $._spacer;
    }

    function isEmpty(StringStorage storage $) internal view returns (bool) {
        return uint256($._spacer) & 0xff == uint256(0);
    }

    function length(StringStorage storage $) internal view returns (uint256) {
        return bytesStorage($)._data.length;
    }

    function get(StringStorage storage $) internal view returns (string memory) {
        return string(bytesStorage($)._data);
    }

    function uint8At(StringStorage storage $, uint256 i) internal view returns (uint8) {
        return uint8(bytesStorage($)._data[i]);
    }

    function bytesStorage(StringStorage storage $)
        internal
        pure
        returns (BytesStorage storage casted)
    {
        assembly {
            casted.slot := $.slot
        }
    }

    function toString(uint256 value) internal pure returns (string memory result) {
        if (value == 0) {
            result = new string(1);
            bytes(result)[0] = '0';
            return result;
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        result = new string(digits);
        bytes memory bresult = bytes(result);
        uint256 k = digits;
        while (value != 0) {
            k--;
            bresult[k] = bytes1(uint8(48 + value % 10));
            value /= 10;
        }
    }

    function toString(int256 value) internal pure returns (string memory result) {
        if (value >= 0) return toString(uint256(value));
        uint256 absValue = uint256(-value);
        string memory absStr = toString(absValue);
        result = new string(bytes(absStr).length + 1);
        bytes(result)[0] = '-';
        for (uint256 i = 0; i < bytes(absStr).length; i++) {
            bytes(result)[i + 1] = bytes(absStr)[i];
        }
    }

    function toHexString(uint256 value, uint256 byteCount)
        internal
        pure
        returns (string memory result)
    {
        result = toHexStringNoPrefix(value, byteCount);
        bytes memory bresult = bytes(result);
        bytes memory newResult = new string(bresult.length + 2);
        bytes(newResult)[0] = '0';
        bytes(newResult)[1] = 'x';
        for (uint256 i = 0; i < bresult.length; i++) {
            bytes(newResult)[i + 2] = bresult[i];
        }
        result = string(newResult);
    }

    function toHexStringNoPrefix(uint256 value, uint256 byteCount)
        internal
        pure
        returns (string memory result)
    {
        bytes memory hexChars = hex"30313233343536373839616263646566";
        result = new string(byteCount * 2);
        bytes memory bresult = bytes(result);
        for (uint256 i = 0; i < byteCount; i++) {
            uint8 b = uint8((value >> ((byteCount - 1 - i) * 8)) & 0xff);
            bresult[i * 2] = hexChars[b >> 4];
            bresult[i * 2 + 1] = hexChars[b & 0x0f];
        }
    }

    function toHexString(uint256 value) internal pure returns (string memory result) {
        result = toHexStringNoPrefix(value);
        bytes memory bresult = bytes(result);
        bytes memory newResult = new string(bresult.length + 2);
        bytes(newResult)[0] = '0';
        bytes(newResult)[1] = 'x';
        for (uint256 i = 0; i < bresult.length; i++) {
            bytes(newResult)[i + 2] = bresult[i];
        }
        result = string(newResult);
    }

    function toMinimalHexString(uint256 value) internal pure returns (string memory result) {
        result = toHexStringNoPrefix(value);
        bytes memory bresult = bytes(result);
        uint256 offset = 0;
        if (bresult.length > 1 && bresult[0] == '0') {
            offset = 1;
        }
        bytes memory newResult = new string(bresult.length - offset + 2);
        bytes(newResult)[0] = '0';
        bytes(newResult)[1] = 'x';
        for (uint256 i = offset; i < bresult.length; i++) {
            bytes(newResult)[i - offset + 2] = bresult[i];
        }
        result = string(newResult);
    }

    function toMinimalHexStringNoPrefix(uint256 value)
        internal
        pure
        returns (string memory result)
    {
        result = toHexStringNoPrefix(value);
        bytes memory bresult = bytes(result);
        uint256 offset = 0;
        if (bresult.length > 1 && bresult[0] == '0') {
            offset = 1;
        }
        bytes memory newResult = new string(bresult.length - offset);
        for (uint256 i = offset; i < bresult.length; i++) {
            bytes(newResult)[i - offset] = bresult[i];
        }
        result = string(newResult);
    }

    function toHexStringNoPrefix(uint256 value) internal pure returns (string memory result) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits = 0;
        while (temp != 0) {
            digits++;
            temp >>= 4;
        }
        bytes memory hexChars = hex"30313233343536373839616263646566";
        result = new string(digits);
        bytes memory bresult = bytes(result);
        uint256 k = digits;
        while (value != 0) {
            k--;
            bresult[k] = hexChars[value & 0x0f];
            value >>= 4;
        }
    }

    function toHexStringChecksummed(address value) internal pure returns (string memory result) {
        result = toHexString(value);
        bytes memory bresult = bytes(result);
        bytes memory addrBytes = new bytes(20);
        for (uint256 i = 0; i < 20; i++) {
            addrBytes[i] = bytes1(uint8(uint160(value) >> (8 * (19 - i))));
        }
        bytes32 hash = sha256(abi.encodePacked(addrBytes));
        for (uint256 i = 0; i < 20; i++) {
            uint8 b = uint8(hash[i]);
            if (b >= 8) {
                uint256 idx = 2 + i * 2 + 1;
                if (bresult[idx] >= 'a' && bresult[idx] <= 'f') {
                    bresult[idx] = bytes1(uint8(bresult[idx]) - 32);
                }
            }
        }
        result = string(bresult);
    }

    function toHexString(address value) internal pure returns (string memory result) {
        result = toHexStringNoPrefix(value);
        bytes memory bresult = bytes(result);
        bytes memory newResult = new string(bresult.length + 2);
        bytes(newResult)[0] = '0';
        bytes(newResult)[1] = 'x';
        for (uint256 i = 0; i < bresult.length; i++) {
            bytes(newResult)[i + 2] = bresult[i];
        }
        result = string(newResult);
    }

    function toHexStringNoPrefix(address value) internal pure returns (string memory result) {
        bytes memory hexChars = hex"30313233343536373839616263646566";
        result = new string(40);
        bytes memory bresult = bytes(result);
        uint160 addr = uint160(value);
        for (uint256 i = 0; i < 20; i++) {
            uint8 b = uint8(addr >> (8 * (19 - i)));
            bresult[i * 2] = hexChars[b >> 4];
            bresult[i * 2 + 1] = hexChars[b & 0x0f];
        }
    }

    function toHexString(bytes memory raw) internal pure returns (string memory result) {
        result = toHexStringNoPrefix(raw);
        bytes memory bresult = bytes(result);
        bytes memory newResult = new string(bresult.length + 2);
        bytes(newResult)[0] = '0';
        bytes(newResult)[1] = 'x';
        for (uint256 i = 0; i < bresult.length; i++) {
            bytes(newResult)[i + 2] = bresult[i];
        }
        result = string(newResult);
    }

    function toHexStringNoPrefix(bytes memory raw) internal pure returns (string memory result) {
        bytes memory hexChars = hex"30313233343536373839616263646566";
        result = new string(raw.length * 2);
        bytes memory bresult = bytes(result);
        for (uint256 i = 0; i < raw.length; i++) {
            uint8 b = uint8(raw[i]);
            bresult[i * 2] = hexChars[b >> 4];
            bresult[i * 2 + 1] = hexChars[b & 0x0f];
        }
    }

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

    function is7BitASCII(string memory s) internal pure returns (bool result) {
        bytes memory b = bytes(s);
        for (uint256 i = 0; i < b.length; i++) {
            if (uint8(b[i]) > 0x7F) {
                return false;
            }
        }
        return true;
    }

    function is7BitASCII(string memory s, uint128 allowed) internal pure returns (bool result) {
        bytes memory b = bytes(s);
        for (uint256 i = 0; i < b.length; i++) {
            uint8 c = uint8(b[i]);
            if (c > 0x7F) {
                return false;
            }
            if ((allowed >> c) & 1 == 0) {
                return false;
            }
        }
        return true;
    }

    function to7BitASCIIAllowedLookup(string memory s) internal pure returns (uint128 result) {
        bytes memory b = bytes(s);
        result = 0;
        for (uint256 i = 0; i < b.length; i++) {
            uint8 c = uint8(b[i]);
            if (c > 0x7F) {
                revert("Non-7-bit ASCII character");
            }
            result |= uint128(1) << c;
        }
    }

    function replace(string memory subject, string memory needle, string memory replacement)
        internal
        pure
        returns (string memory)
    {
        return string(bytesStorageReplace(bytes(subject), bytes(needle), bytes(replacement)));
    }

    function indexOf(string memory subject, string memory needle, uint256 from)
        internal
        pure
        returns (uint256)
    {
        return bytesStorageIndexOf(bytes(subject), bytes(needle), from);
    }

    function indexOf(string memory subject, string memory needle) internal pure returns (uint256) {
        return bytesStorageIndexOf(bytes(subject), bytes(needle), 0);
    }

    function lastIndexOf(string memory subject, string memory needle, uint256 from)
        internal
        pure
        returns (uint256)
    {
        return bytesStorageLastIndexOf(bytes(subject), bytes(needle), from);
    }

    function lastIndexOf(string memory subject, string memory needle)
        internal
        pure
        returns (uint256)
    {
        return bytesStorageLastIndexOf(bytes(subject), bytes(needle), type(uint256).max);
    }

    function contains(string memory subject, string memory needle) internal pure returns (bool) {
        return bytesStorageContains(bytes(subject), bytes(needle));
    }

    function startsWith(string memory subject, string memory needle) internal pure returns (bool) {
        return bytesStorageStartsWith(bytes(subject), bytes(needle));
    }

    function endsWith(string memory subject, string memory needle) internal pure returns (bool) {
        return bytesStorageEndsWith(bytes(subject), bytes(needle));
    }

    function repeat(string memory subject, uint256 times) internal pure returns (string memory) {
        return string(bytesStorageRepeat(bytes(subject), times));
    }

    function slice(string memory subject, uint256 start, uint256 end)
        internal
        pure
        returns (string memory)
    {
        return string(bytesStorageSlice(bytes(subject), start, end));
    }

    function slice(string memory subject, uint256 start) internal pure returns (string memory) {
        return string(bytesStorageSlice(bytes(subject), start, type(uint256).max));
    }

    function indicesOf(string memory subject, string memory needle)
        internal
        pure
        returns (uint256[] memory)
    {
        return bytesStorageIndicesOf(bytes(subject), bytes(needle));
    }

    function split(string memory subject, string memory delimiter)
        internal
        pure
        returns (string[] memory result)
    {
        bytes[] memory a = bytesStorageSplit(bytes(subject), bytes(delimiter));
        result = new string[](a.length);
        for (uint256 i = 0; i < a.length; i++) {
            result[i] = string(a[i]);
        }
    }

    function concat(string memory a, string memory b) internal pure returns (string memory) {
        return string(bytesStorageConcat(bytes(a), bytes(b)));
    }

    function toCase(string memory subject, bool toUpper)
        internal
        pure
        returns (string memory result)
    {
        bytes memory b = bytes(subject);
        result = new string(b.length);
        bytes memory bresult = bytes(result);
        for (uint256 i = 0; i < b.length; i++) {
            uint8 c = uint8(b[i]);
            if (toUpper) {
                if (c >= 97 && c <= 122) {
                    c -= 32;
                }
            } else {
                if (c >= 65 && c <= 90) {
                    c += 32;
                }
            }
            bresult[i] = bytes1(c);
        }
    }

    function fromSmallString(bytes32 s) internal pure returns (string memory result) {
        uint256 n = 0;
        for (uint256 i = 0; i < 32; i++) {
            if (s[i] == 0) {
                n = i;
                break;
            }
        }
        if (n == 0 && s[0] != 0) {
            n = 32;
        }
        result = new string(n);
        bytes memory bresult = bytes(result);
        for (uint256 i = 0; i < n; i++) {
            bresult[i] = s[i];
        }
    }

    function normalizeSmallString(bytes32 s) internal pure returns (bytes32 result) {
        result = s;
        for (uint256 i = 0; i < 32; i++) {
            if (result[i] == 0) {
                for (uint256 j = i; j < 32; j++) {
                    result[j] = 0;
                }
                break;
            }
        }
    }

    function toSmallString(string memory s) internal pure returns (bytes32 result) {
        bytes memory b = bytes(s);
        if (b.length > 32) {
            revert("String too long");
        }
        result = bytes32(0);
        for (uint256 i = 0; i < b.length; i++) {
            result |= bytes32(b[i]) >> (i * 8);
        }
    }

    function lower(string memory subject) internal pure returns (string memory result) {
        result = toCase(subject, false);
    }

    function upper(string memory subject) internal pure returns (string memory result) {
        result = toCase(subject, true);
    }

    function escapeHTML(string memory s) internal pure returns (string memory result) {
        bytes memory b = bytes(s);
        bytes memory escaped = new bytes(b.length * 6);
        uint256 j = 0;
        for (uint256 i = 0; i < b.length; i++) {
            uint8 c = uint8(b[i]);
            if (c == 38) {
                escaped[j++] = '&';
                escaped[j++] = 'a';
                escaped[j++] = 'm';
                escaped[j++] = 'p';
                escaped[j++] = ';';
            } else if (c == 60) {
                escaped[j++] = '&';
                escaped[j++] = 'l';
                escaped[j++] = 't';
                escaped[j++] = ';';
            } else if (c == 62) {
                escaped[j++] = '&';
                escaped[j++] = 'g';
                escaped[j++] = 't';
                escaped[j++] = ';';
            } else if (c == 34) {
                escaped[j++] = '&';
                escaped[j++] = 'q';
                escaped[j++] = 'u';
                escaped[j++] = 'o';
                escaped[j++] = 't';
                escaped[j++] = ';';
            } else if (c == 39) {
                escaped[j++] = '&';
                escaped[j++] = '#';
                escaped[j++] = '3';
                escaped[j++] = '9';
                escaped[j++] = ';';
            } else {
                escaped[j++] = bytes1(c);
            }
        }
        result = new string(j);
        bytes memory bresult = bytes(result);
        for (uint256 i = 0; i < j; i++) {
            bresult[i] = escaped[i];
        }
    }

    function escapeJSON(string memory s, bool addDoubleQuotes)
        internal
        pure
        returns (string memory result)
    {
        bytes memory b = bytes(s);
        bytes memory escaped = new bytes(b.length * 6 + 2);
        uint256 j = 0;
        if (addDoubleQuotes) {
            escaped[j++] = '"';
        }
        for (uint256 i = 0; i < b.length; i++) {
            uint8 c = uint8(b[i]);
            if (c == 34) {
                escaped[j++] = '\\';
                escaped[j++] = '"';
            } else if (c == 92) {
                escaped[j++] = '\\';
                escaped[j++] = '\\';
            } else if (c == 8) {
                escaped[j++] = '\\';
                escaped[j++] = 'b';
            } else if (c == 12) {
                escaped[j++] = '\\';
                escaped[j++] = 'f';
            } else if (c == 10) {
                escaped[j++] = '\\';
                escaped[j++] = 'n';
            } else if (c == 13) {
                escaped[j++] = '\\';
                escaped[j++] = 'r';
            } else if (c == 9) {
                escaped[j++] = '\\';
                escaped[j++] = 't';
            } else if (c < 0x20) {
                escaped[j++] = '\\';
                escaped[j++] = 'u';
                escaped[j++] = '0';
                escaped[j++] = '0';
                bytes memory hexChars = hex"30313233343536373839616263646566";
                escaped[j++] = hexChars[c >> 4];
                escaped[j++] = hexChars[c & 0x0f];
            } else {
                escaped[j++] = bytes1(c);
            }
        }
        if (addDoubleQuotes) {
            escaped[j++] = '"';
        }
        result = new string(j);
        bytes memory bresult = bytes(result);
        for (uint256 i = 0; i < j; i++) {
            bresult[i] = escaped[i];
        }
    }

    function escapeJSON(string memory s) internal pure returns (string memory result) {
        result = escapeJSON(s, false);
    }

    function encodeURIComponent(string memory s) internal pure returns (string memory result) {
        bytes memory b = bytes(s);
        bytes memory encoded = new bytes(b.length * 3);
        uint256 j = 0;
        bytes memory hexChars = hex"30313233343536373839414243444546";
        for (uint256 i = 0; i < b.length; i++) {
            uint8 c = uint8(b[i]);
            if ((c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) ||
                c == 45 || c == 95 || c == 46 || c == 33 || c == 126 || c == 42 || c == 39 || c == 40 || c == 41) {
                encoded[j++] = bytes1(c);
            } else {
                encoded[j++] = '%';
                encoded[j++] = hexChars[c >> 4];
                encoded[j++] = hexChars[c & 0x0f];
            }
        }
        result = new string(j);
        bytes memory bresult = bytes(result);
        for (uint256 i = 0; i < j; i++) {
            bresult[i] = encoded[i];
        }
    }

    function eq(string memory a, string memory b) internal pure returns (bool result) {
        return sha256(bytes(a)) == sha256(bytes(b));
    }

    function eqs(string memory a, bytes32 b) internal pure returns (bool result) {
        bytes memory bBytes = new bytes(32);
        for (uint256 i = 0; i < 32; i++) {
            bBytes[i] = b[i];
        }
        uint256 len = 32;
        while (len > 0 && bBytes[len - 1] == 0) {
            len--;
        }
        bytes memory trimmed = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            trimmed[i] = bBytes[i];
        }
        return eq(a, string(trimmed));
    }

    function cmp(string memory a, string memory b) internal pure returns (int256) {
        return bytesStorageCmp(bytes(a), bytes(b));
    }

    function packOne(string memory a) internal pure returns (bytes32 result) {
        bytes memory b = bytes(a);
        if (b.length > 31) {
            revert("String too long");
        }
        result = bytes32(0);
        for (uint256 i = 0; i < b.length; i++) {
            result |= bytes32(b[i]) >> (i * 8);
        }
    }

    function unpackOne(bytes32 packed) internal pure returns (string memory result) {
        uint256 len = 0;
        for (uint256 i = 0; i < 32; i++) {
            if (packed[i] == 0) {
                len = i;
                break;
            }
        }
        if (len == 0 && packed[0] != 0) {
            len = 32;
        }
        result = new string(len);
        bytes memory bresult = bytes(result);
        for (uint256 i = 0; i < len; i++) {
            bresult[i] = packed[i];
        }
    }

    function packTwo(string memory a, string memory b) internal pure returns (bytes32 result) {
        bytes memory ba = bytes(a);
        bytes memory bb = bytes(b);
        if (ba.length + bb.length > 30) {
            revert("Strings too long");
        }
        result = bytes32(0);
        for (uint256 i = 0; i < ba.length; i++) {
            result |= bytes32(ba[i]) >> (i * 8);
        }
        for (uint256 i = 0; i < bb.length; i++) {
            result |= bytes32(bb[i]) >> ((ba.length + i) * 8);
        }
    }

    function unpackTwo(bytes32 packed)
        internal
        pure
        returns (string memory resultA, string memory resultB)
    {
        bytes memory allBytes = new bytes(30);
        for (uint256 i = 0; i < 30; i++) {
            allBytes[i] = packed[i];
        }
        uint256 lenA = 0;
        while (lenA < 30 && allBytes[lenA] != 0) {
            lenA++;
        }
        resultA = new string(lenA);
        bytes memory bresultA = bytes(resultA);
        for (uint256 i = 0; i < lenA; i++) {
            bresultA[i] = allBytes[i];
        }
        uint256 lenB = 0;
        while (lenA + lenB < 30 && allBytes[lenA + lenB] != 0) {
            lenB++;
        }
        resultB = new string(lenB);
        bytes memory bresultB = bytes(resultB);
        for (uint256 i = 0; i < lenB; i++) {
            bresultB[i] = allBytes[lenA + i];
        }
    }

    function directReturn(string memory a) internal pure {
        bytes memory b = bytes(a);
        bytes memory ret = new bytes(b.length + 32);
        for (uint256 i = 0; i < 32; i++) {
            ret[i] = 0;
        }
        ret[31] = bytes1(uint8(32));
        for (uint256 i = 0; i < b.length; i++) {
            ret[i + 32] = b[i];
        }
        assembly {
            return(add(ret, 32), mload(ret))
        }
    }

    struct BytesStorage {
        bytes _data;
    }

    function set(BytesStorage storage $, string memory s) internal {
        $._data = bytes(s);
    }

    function setCalldata(BytesStorage storage $, string calldata s) internal {
        $._data = bytes(s);
    }

    function length(BytesStorage storage $) internal view returns (uint256) {
        return $._data.length;
    }

    function get(BytesStorage storage $) internal view returns (bytes memory) {
        return $._data;
    }

    function uint8At(BytesStorage storage $, uint256 i) internal view returns (uint8) {
        return uint8($._data[i]);
    }

    function bytesStorageReplace(bytes memory subject, bytes memory needle, bytes memory replacement)
        internal
        pure
        returns (bytes memory)
    {
        if (needle.length == 0) {
            return subject;
        }
        uint256[] memory indices = bytesStorageIndicesOf(subject, needle);
        if (indices.length == 0) {
            return subject;
        }
        uint256 newLen = subject.length + indices.length * (replacement.length - needle.length);
        bytes memory result = new bytes(newLen);
        uint256 s = 0;
        uint256 r = 0;
        for (uint256 i = 0; i < indices.length; i++) {
            uint256 idx = indices[i];
            for (uint256 j = s; j < idx; j++) {
                result[r++] = subject[j];
            }
            for (uint256 j = 0; j < replacement.length; j++) {
                result[r++] = replacement[j];
            }
            s = idx + needle.length;
        }
        for (uint256 j = s; j < subject.length; j++) {
            result[r++] = subject[j];
        }
        return result;
    }

    function bytesStorageIndexOf(bytes memory subject, bytes memory needle, uint256 from)
        internal
        pure
        returns (uint256)
    {
        if (needle.length == 0) {
            return from <= subject.length ? from : NOT_FOUND;
        }
        if (from + needle.length > subject.length) {
            return NOT_FOUND;
        }
        for (uint256 i = from; i <= subject.length - needle.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < needle.length; j++) {
                if (subject[i + j] != needle[j]) {
                    found = false;
                    break;
                }
            }
            if (found) {
                return i;
            }
        }
        return NOT_FOUND;
    }

    function bytesStorageLastIndexOf(bytes memory subject, bytes memory needle, uint256 from)
        internal
        pure
        returns (uint256)
    {
        if (needle.length == 0) {
            return from < subject.length ? from : subject.length;
        }
        uint256 end = from;
        if (end > subject.length - needle.length) {
            end = subject.length - needle.length;
        }
        for (uint256 i = end; ; i--) {
            bool found = true;
            for (uint256 j = 0; j < needle.length; j++) {
                if (subject[i + j] != needle[j]) {
                    found = false;
                    break;
                }
            }
            if (found) {
                return i;
            }
            if (i == 0) {
                break;
            }
        }
        return NOT_FOUND;
    }

    function bytesStorageContains(bytes memory subject, bytes memory needle) internal pure returns (bool) {
        return bytesStorageIndexOf(subject, needle, 0) != NOT_FOUND;
    }

    function bytesStorageStartsWith(bytes memory subject, bytes memory needle) internal pure returns (bool) {
        if (needle.length > subject.length) {
            return false;
        }
        for (uint256 i = 0; i < needle.length; i++) {
            if (subject[i] != needle[i]) {
                return false;
            }
        }
        return true;
    }

    function bytesStorageEndsWith(bytes memory subject, bytes memory needle) internal pure returns (bool) {
        if (needle.length > subject.length) {
            return false;
        }
        for (uint256 i = 0; i < needle.length; i++) {
            if (subject[subject.length - needle.length + i] != needle[i]) {
                return false;
            }
        }
        return true;
    }

    function bytesStorageRepeat(bytes memory subject, uint256 times) internal pure returns (bytes memory) {
        bytes memory result = new bytes(subject.length * times);
        for (uint256 i = 0; i < times; i++) {
            for (uint256 j = 0; j < subject.length; j++) {
                result[i * subject.length + j] = subject[j];
            }
        }
        return result;
    }

    function bytesStorageSlice(bytes memory subject, uint256 start, uint256 end)
        internal
        pure
        returns (bytes memory)
    {
        if (end > subject.length) {
            end = subject.length;
        }
        if (start > end) {
            return new bytes(0);
        }
        bytes memory result = new bytes(end - start);
        for (uint256 i = start; i < end; i++) {
            result[i - start] = subject[i];
        }
        return result;
    }

    function bytesStorageIndicesOf(bytes memory subject, bytes memory needle)
        internal
        pure
        returns (uint256[] memory)
    {
        if (needle.length == 0) {
            return new uint256[](0);
        }
        uint256 count = 0;
        uint256[] memory temp = new uint256[](subject.length);
        uint256 idx = 0;
        while (idx <= subject.length - needle.length) {
            bool found = true;
            for (uint256 j = 0; j < needle.length; j++) {
                if (subject[idx + j] != needle[j]) {
                    found = false;
                    break;
                }
            }
            if (found) {
                temp[count++] = idx;
                idx += needle.length;
            } else {
                idx++;
            }
        }
        uint256[] memory result = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = temp[i];
        }
        return result;
    }

    function bytesStorageSplit(bytes memory subject, bytes memory delimiter)
        internal
        pure
        returns (bytes[] memory)
    {
        if (delimiter.length == 0) {
            bytes[] memory result = new bytes[](subject.length);
            for (uint256 i = 0; i < subject.length; i++) {
                result[i] = new bytes(1);
                result[i][0] = subject[i];
            }
            return result;
        }
        uint256[] memory indices = bytesStorageIndicesOf(subject, delimiter);
        bytes[] memory result = new bytes[](indices.length + 1);
        uint256 s = 0;
        for (uint256 i = 0; i < indices.length; i++) {
            uint256 idx = indices[i];
            result[i] = bytesStorageSlice(subject, s, idx);
            s = idx + delimiter.length;
        }
        result[indices.length] = bytesStorageSlice(subject, s, subject.length);
        return result;
    }

    function bytesStorageConcat(bytes memory a, bytes memory b) internal pure returns (bytes memory) {
        bytes memory result = new bytes(a.length + b.length);
        for (uint256 i = 0; i < a.length; i++) {
            result[i] = a[i];
        }
        for (uint256 i = 0; i < b.length; i++) {
            result[a.length + i] = b[i];
        }
        return result;
    }

    function bytesStorageCmp(bytes memory a, bytes memory b) internal pure returns (int256) {
        uint256 minLen = a.length < b.length ? a.length : b.length;
        for (uint256 i = 0; i < minLen; i++) {
            if (a[i] < b[i]) {
                return -1;
            }
            if (a[i] > b[i]) {
                return 1;
            }
        }
        if (a.length < b.length) {
            return -1;
        }
        if (a.length > b.length) {
            return 1;
        }
        return 0;
    }
}