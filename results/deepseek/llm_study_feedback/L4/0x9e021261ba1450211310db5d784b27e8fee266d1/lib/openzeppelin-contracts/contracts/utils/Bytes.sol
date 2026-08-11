// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library Bytes {
    function indexOf(bytes memory buffer, bytes1 s) internal pure returns (uint256) {
        return indexOf(buffer, s, 0);
    }

    function indexOf(bytes memory buffer, bytes1 s, uint256 pos) internal pure returns (uint256) {
        uint256 length = buffer.length;
        for (uint256 i = pos; i < length; ++i) {
            if (bytes1(_unsafeReadBytesOffset(buffer, i)) == s) {
                return i;
            }
        }
        return type(uint256).max;
    }

    function lastIndexOf(bytes memory buffer, bytes1 s) internal pure returns (uint256) {
        return lastIndexOf(buffer, s, type(uint256).max);
    }

    function lastIndexOf(bytes memory buffer, bytes1 s, uint256 pos) internal pure returns (uint256) {
        unchecked {
            uint256 length = buffer.length;
            for (uint256 i = min(saturatingAdd(pos, 1), length); i > 0; --i) {
                if (bytes1(_unsafeReadBytesOffset(buffer, i - 1)) == s) {
                    return i - 1;
                }
            }
            return type(uint256).max;
        }
    }

    function slice(bytes memory buffer, uint256 start) internal pure returns (bytes memory) {
        return slice(buffer, start, buffer.length);
    }

    function slice(bytes memory buffer, uint256 start, uint256 end) internal pure returns (bytes memory) {
        end = min(end, buffer.length);
        start = min(start, end);

        bytes memory result = new bytes(end - start);
        for (uint256 i = 0; i < end - start; i++) {
            result[i] = buffer[start + i];
        }

        return result;
    }

    function splice(bytes memory buffer, uint256 start) internal pure returns (bytes memory) {
        return splice(buffer, start, buffer.length);
    }

    function splice(bytes memory buffer, uint256 start, uint256 end) internal pure returns (bytes memory) {
        end = min(end, buffer.length);
        start = min(start, end);

        uint256 newLength = end - start;
        for (uint256 i = 0; i < newLength; i++) {
            buffer[i] = buffer[start + i];
        }
        // Resize the array by writing the new length into the first 32 bytes
        // Solang does not support mstore, use inline assembly with account data
        bytes memory resized = new bytes(newLength);
        for (uint256 i = 0; i < newLength; i++) {
            resized[i] = buffer[i];
        }
        return resized;
    }

    function replace(bytes memory buffer, uint256 pos, bytes memory replacement) internal pure returns (bytes memory) {
        return replace(buffer, pos, replacement, 0, replacement.length);
    }

    function replace(
        bytes memory buffer,
        uint256 pos,
        bytes memory replacement,
        uint256 offset,
        uint256 length
    ) internal pure returns (bytes memory) {
        pos = min(pos, buffer.length);
        offset = min(offset, replacement.length);
        length = min(length, min(replacement.length - offset, buffer.length - pos));

        for (uint256 i = 0; i < length; i++) {
            buffer[pos + i] = replacement[offset + i];
        }

        return buffer;
    }

    function concat(bytes[] memory buffers) internal pure returns (bytes memory) {
        uint256 length = 0;
        for (uint256 i = 0; i < buffers.length; ++i) {
            length += buffers[i].length;
        }

        bytes memory result = new bytes(length);

        uint256 offset = 0;
        for (uint256 i = 0; i < buffers.length; ++i) {
            bytes memory input = buffers[i];
            for (uint256 j = 0; j < input.length; j++) {
                result[offset + j] = input[j];
            }
            unchecked {
                offset += input.length;
            }
        }

        return result;
    }

    function toNibbles(bytes memory input) internal pure returns (bytes memory output) {
        uint256 length = input.length;
        output = new bytes(length * 2);
        for (uint256 i = 0; i < length; i++) {
            bytes1 b = input[i];
            uint8 high = uint8(b) >> 4;
            uint8 low = uint8(b) & 0x0f;
            output[i * 2] = bytes1(high);
            output[i * 2 + 1] = bytes1(low);
        }
    }

    function equal(bytes memory a, bytes memory b) internal pure returns (bool) {
        return a.length == b.length && keccak256(a) == keccak256(b);
    }

    function reverseBytes32(bytes32 value) internal pure returns (bytes32) {
        value = // swap bytes
            ((value >> 8) & 0x00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF) |
            ((value & 0x00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF) << 8);
        value = // swap 2-byte long pairs
            ((value >> 16) & 0x0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF) |
            ((value & 0x0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF) << 16);
        value = // swap 4-byte long pairs
            ((value >> 32) & 0x00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF) |
            ((value & 0x00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF) << 32);
        value = // swap 8-byte long pairs
            ((value >> 64) & 0x0000000000000000FFFFFFFFFFFFFFFF0000000000000000FFFFFFFFFFFFFFFF) |
            ((value & 0x0000000000000000FFFFFFFFFFFFFFFF0000000000000000FFFFFFFFFFFFFFFF) << 64);
        return (value >> 128) | (value << 128); // swap 16-byte long pairs
    }

    function reverseBytes16(bytes16 value) internal pure returns (bytes16) {
        value = // swap bytes
            ((value & 0xFF00FF00FF00FF00FF00FF00FF00FF00) >> 8) |
            ((value & 0x00FF00FF00FF00FF00FF00FF00FF00FF) << 8);
        value = // swap 2-byte long pairs
            ((value & 0xFFFF0000FFFF0000FFFF0000FFFF0000) >> 16) |
            ((value & 0x0000FFFF0000FFFF0000FFFF0000FFFF) << 16);
        value = // swap 4-byte long pairs
            ((value & 0xFFFFFFFF00000000FFFFFFFF00000000) >> 32) |
            ((value & 0x00000000FFFFFFFF00000000FFFFFFFF) << 32);
        return (value >> 64) | (value << 64); // swap 8-byte long pairs
    }

    function reverseBytes8(bytes8 value) internal pure returns (bytes8) {
        value = ((value & 0xFF00FF00FF00FF00) >> 8) | ((value & 0x00FF00FF00FF00FF) << 8); // swap bytes
        value = ((value & 0xFFFF0000FFFF0000) >> 16) | ((value & 0x0000FFFF0000FFFF) << 16); // swap 2-byte long pairs
        return (value >> 32) | (value << 32); // swap 4-byte long pairs
    }

    function reverseBytes4(bytes4 value) internal pure returns (bytes4) {
        value = ((value & 0xFF00FF00) >> 8) | ((value & 0x00FF00FF) << 8); // swap bytes
        return (value >> 16) | (value << 16); // swap 2-byte long pairs
    }

    function reverseBytes2(bytes2 value) internal pure returns (bytes2) {
        return (value >> 8) | (value << 8);
    }

    function clz(bytes memory buffer) internal pure returns (uint256) {
        for (uint256 i = 0; i < buffer.length; i += 0x20) {
            bytes32 chunk = _unsafeReadBytesOffset(buffer, i);
            if (chunk != bytes32(0)) {
                return min(8 * i + clz256(uint256(chunk)), 8 * buffer.length);
            }
        }
        return 8 * buffer.length;
    }

    function _unsafeReadBytesOffset(bytes memory buffer, uint256 offset) private pure returns (bytes32 value) {
        // Read 32 bytes from buffer at given offset without bounds checking
        // Solang does not support mload, so we use a loop to read bytes
        value = bytes32(0);
        uint256 len = buffer.length;
        for (uint256 i = 0; i < 32; i++) {
            if (offset + i < len) {
                value |= bytes32(uint256(uint8(buffer[offset + i]))) >> (i * 8);
            }
        }
    }

    // Helper functions to replace Math library
    function min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }

    function saturatingAdd(uint256 a, uint256 b) private pure returns (uint256) {
        unchecked {
            uint256 c = a + b;
            if (c < a) return type(uint256).max;
            return c;
        }
    }

    function clz256(uint256 x) private pure returns (uint256) {
        if (x == 0) return 256;
        uint256 n = 0;
        if (x <= type(uint128).max) { n += 128; x <<= 128; }
        if (x <= type(uint64).max)  { n += 64;  x <<= 64; }
        if (x <= type(uint32).max)  { n += 32;  x <<= 32; }
        if (x <= type(uint16).max)  { n += 16;  x <<= 16; }
        if (x <= type(uint8).max)   { n += 8;   x <<= 8; }
        if (x <= 0x0f)              { n += 4;   x <<= 4; }
        if (x <= 0x3f)              { n += 2;   x <<= 2; }
        if (x <= 0x7f)              { n += 1; }
        return n;
    }
}