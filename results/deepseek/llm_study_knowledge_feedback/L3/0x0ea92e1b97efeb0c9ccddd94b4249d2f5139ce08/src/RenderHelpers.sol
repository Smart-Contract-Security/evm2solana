// SPDX-License-Identifier: MIT

library RenderHelpers {
    uint64 internal constant SCALE = 10000;

    function readU32(bytes memory data, uint64 offset) internal pure returns (uint64) {
        return (uint64(uint8(data[offset])) << 24)
             | (uint64(uint8(data[offset + 1])) << 16)
             | (uint64(uint8(data[offset + 2])) << 8)
             | uint64(uint8(data[offset + 3]));
    }

    function readU16(bytes memory data, uint64 offset) internal pure returns (uint64) {
        return (uint64(uint8(data[offset])) << 8) | uint64(uint8(data[offset + 1]));
    }

    function readLengthPrefixed(bytes memory data, uint64 off) internal pure returns (string memory) {
        uint8 len = uint8(data[off]);
        bytes memory out = new bytes(len);
        for (uint64 i = 0; i < len; i++) out[i] = data[off + 1 + i];
        return string(out);
    }

    function toString(uint64 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint64 temp = value;
        uint64 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint64(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function fix(uint64 v) internal pure returns (string memory) {
        uint64 ip = v / SCALE;
        uint64 fp = v % SCALE;
        if (fp == 0) return toString(ip);
        uint64 digits = 4;
        while (digits > 1 && fp % 10 == 0) { fp /= 10; digits--; }
        string memory fs = toString(fp);
        while (bytes(fs).length < digits) fs = string.concat("0", fs);
        return string.concat(toString(ip), ".", fs);
    }

    function toHexColor(bytes4 c) internal pure returns (string memory) {
        bytes memory out = new bytes(9);
        out[0] = "#";
        for (uint64 i = 0; i < 4; i++) {
            uint8 b = uint8(c[i]);
            out[1 + i * 2] = _nib(b >> 4);
            out[2 + i * 2] = _nib(b & 0xf);
        }
        return string(out);
    }

    function _nib(uint8 v) private pure returns (bytes1) {
        return v < 10 ? bytes1(uint8(0x30 + v)) : bytes1(uint8(0x57 + v));
    }

    function utf8Len(uint8 b) internal pure returns (uint64) {
        if (b < 0x80) return 1;
        if (b < 0xC0) return 1;
        if (b < 0xE0) return 2;
        if (b < 0xF0) return 3;
        return 4;
    }
}