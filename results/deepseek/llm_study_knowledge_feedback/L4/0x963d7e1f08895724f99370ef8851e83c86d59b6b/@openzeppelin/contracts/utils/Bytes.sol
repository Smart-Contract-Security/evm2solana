// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.6.0) (utils/Bytes.sol)

/**
 * @dev Bytes operations.
 */
library Bytes {
    /**
     * @dev Forward search for `s` in `buffer`
     * * If `s` is present in the buffer, returns the index of the first instance
     * * If `s` is not present in the buffer, returns type(uint64).max
     *
     * NOTE: replicates the behavior of https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Array/indexOf[Javascript's `Array.indexOf`]
     */
    function indexOf(bytes memory buffer, bytes1 s) internal pure returns (uint64) {
        return indexOf(buffer, s, 0);
    }

    /**
     * @dev Forward search for `s` in `buffer` starting at position `pos`
     * * If `s` is present in the buffer (at or after `pos`), returns the index of the next instance
     * * If `s` is not present in the buffer (at or after `pos`), returns type(uint64).max
     *
     * NOTE: replicates the behavior of https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Array/indexOf[Javascript's `Array.indexOf`]
     */
    function indexOf(bytes memory buffer, bytes1 s, uint64 pos) internal pure returns (uint64) {
        uint64 length = uint64(buffer.length);
        for (uint64 i = pos; i < length; ++i) {
            if (bytes1(_unsafeReadBytesOffset(buffer, i)) == s) {
                return i;
            }
        }
        return type(uint64).max;
    }

    /**
     * @dev Backward search for `s` in `buffer`
     * * If `s` is present in the buffer, returns the index of the last instance
     * * If `s` is not present in the buffer, returns type(uint64).max
     *
     * NOTE: replicates the behavior of https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Array/lastIndexOf[Javascript's `Array.lastIndexOf`]
     */
    function lastIndexOf(bytes memory buffer, bytes1 s) internal pure returns (uint64) {
        return lastIndexOf(buffer, s, type(uint64).max);
    }

    /**
     * @dev Backward search for `s` in `buffer` starting at position `pos`
     * * If `s` is present in the buffer (at or before `pos`), returns the index of the previous instance
     * * If `s` is not present in the buffer (at or before `pos`), returns type(uint64).max
     *
     * NOTE: replicates the behavior of https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Array/lastIndexOf[Javascript's `Array.lastIndexOf`]
     */
    function lastIndexOf(bytes memory buffer, bytes1 s, uint64 pos) internal pure returns (uint64) {
        unchecked {
            uint64 length = uint64(buffer.length);
            uint64 start = min(saturatingAdd(pos, 1), length);
            for (uint64 i = start; i > 0; --i) {
                if (bytes1(_unsafeReadBytesOffset(buffer, i - 1)) == s) {
                    return i - 1;
                }
            }
            return type(uint64).max;
        }
    }

    /**
     * @dev Copies the content of `buffer`, from `start` (included) to the end of `buffer` into a new bytes object in
     * memory.
     *
     * NOTE: replicates the behavior of https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Array/slice[Javascript's `Array.slice`]
     */
    function slice(bytes memory buffer, uint64 start) internal pure returns (bytes memory) {
        return slice(buffer, start, uint64(buffer.length));
    }

    /**
     * @dev Copies the content of `buffer`, from `start` (included) to `end` (excluded) into a new bytes object in
     * memory. The `end` argument is truncated to the length of the `buffer`.
     *
     * NOTE: replicates the behavior of https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Array/slice[Javascript's `Array.slice`]
     */
    function slice(bytes memory buffer, uint64 start, uint64 end) internal pure returns (bytes memory) {
        // sanitize
        end = min(end, uint64(buffer.length));
        start = min(start, end);

        // allocate and copy
        bytes memory result = new bytes(end - start);
        uint64 len = end - start;
        for (uint64 i = 0; i < len; ++i) {
            result[i] = buffer[start + i];
        }

        return result;
    }

    /**
     * @dev Moves the content of `buffer`, from `start` (included) to the end of `buffer` to the start of that buffer,
     * and shrinks the buffer length accordingly, effectively overriding the content of buffer with buffer[start:].
     *
     * NOTE: This function modifies the provided buffer in place. If you need to preserve the original buffer, use {slice} instead
     */
    function splice(bytes memory buffer, uint64 start) internal pure returns (bytes memory) {
        return splice(buffer, start, uint64(buffer.length));
    }

    /**
     * @dev Moves the content of `buffer`, from `start` (included) to `end` (excluded) to the start of that buffer,
     * and shrinks the buffer length accordingly, effectively overriding the content of buffer with buffer[start:end].
     * The `end` argument is truncated to the length of the `buffer`.
     *
     * NOTE: This function modifies the provided buffer in place. If you need to preserve the original buffer, use {slice} instead
     */
    function splice(bytes memory buffer, uint64 start, uint64 end) internal pure returns (bytes memory) {
        // sanitize
        end = min(end, uint64(buffer.length));
        start = min(start, end);

        // move and resize
        uint64 newLen = end - start;
        for (uint64 i = 0; i < newLen; ++i) {
            buffer[i] = buffer[start + i];
        }
        // resize by re-allocating
        bytes memory newBuffer = new bytes(newLen);
        for (uint64 i = 0; i < newLen; ++i) {
            newBuffer[i] = buffer[i];
        }
        return newBuffer;
    }

    /**
     * @dev Replaces bytes in `buffer` starting at `pos` with all bytes from `replacement`.
     *
     * Parameters are clamped to valid ranges (i.e. `pos` is clamped to `[0, buffer.length]`).
     * If `pos >= buffer.length`, no replacement occurs and the buffer is returned unchanged.
     *
     * NOTE: This function modifies the provided buffer in place.
     */
    function replace(bytes memory buffer, uint64 pos, bytes memory replacement) internal pure returns (bytes memory) {
        return replace(buffer, pos, replacement, 0, uint64(replacement.length));
    }

    /**
     * @dev Replaces bytes in `buffer` starting at `pos` with bytes from `replacement` starting at `offset`.
     * Copies at most `length` bytes from `replacement` to `buffer`.
     *
     * Parameters are clamped to valid ranges (i.e. `pos` is clamped to `[0, buffer.length]`, `offset` is
     * clamped to `[0, replacement.length]`, and `length` is clamped to `min(length, replacement.length - offset,
     * buffer.length - pos))`. If `pos >= buffer.length` or `offset >= replacement.length`, no replacement occurs
     * and the buffer is returned unchanged.
     *
     * NOTE: This function modifies the provided buffer in place.
     */
    function replace(
        bytes memory buffer,
        uint64 pos,
        bytes memory replacement,
        uint64 offset,
        uint64 length
    ) internal pure returns (bytes memory) {
        // sanitize
        pos = min(pos, uint64(buffer.length));
        offset = min(offset, uint64(replacement.length));
        length = min(length, min(uint64(replacement.length) - offset, uint64(buffer.length) - pos));

        // replace
        for (uint64 i = 0; i < length; ++i) {
            buffer[pos + i] = replacement[offset + i];
        }

        return buffer;
    }

    /**
     * @dev Concatenate an array of bytes into a single bytes object.
     *
     * For fixed bytes types, we recommend using the solidity built-in `bytes.concat` or (equivalent)
     * `abi.encodePacked`.
     */
    function concat(bytes[] memory buffers) internal pure returns (bytes memory) {
        uint64 length = 0;
        for (uint64 i = 0; i < buffers.length; ++i) {
            length += uint64(buffers[i].length);
        }

        bytes memory result = new bytes(length);

        uint64 offset = 0;
        for (uint64 i = 0; i < buffers.length; ++i) {
            bytes memory input = buffers[i];
            uint64 inputLen = uint64(input.length);
            for (uint64 j = 0; j < inputLen; ++j) {
                result[offset + j] = input[j];
            }
            offset += inputLen;
        }

        return result;
    }

    /**
     * @dev Split each byte in `input` into two nibbles (4 bits each)
     *
     * Example: hex"01234567" → hex"0001020304050607"
     */
    function toNibbles(bytes memory input) internal pure returns (bytes memory output) {
        uint64 length = uint64(input.length);
        output = new bytes(length * 2);
        for (uint64 i = 0; i < length; ++i) {
            bytes1 b = input[i];
            output[i * 2] = bytes1(uint8(b) >> 4);
            output[i * 2 + 1] = bytes1(uint8(b) & 0x0f);
        }
    }

    /**
     * @dev Returns true if the two byte buffers are equal.
     */
    function equal(bytes memory a, bytes memory b) internal pure returns (bool) {
        return a.length == b.length && keccak256(a) == keccak256(b);
    }

    /**
     * @dev Reverses the byte order of a bytes32 value, converting between little-endian and big-endian.
     * Inspired by https://graphics.stanford.edu/~seander/bithacks.html#ReverseParallel[Reverse Parallel]
     */
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

    /// @dev Same as {reverseBytes32} but optimized for 128-bit values.
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

    /// @dev Same as {reverseBytes32} but optimized for 64-bit values.
    function reverseBytes8(bytes8 value) internal pure returns (bytes8) {
        value = ((value & 0xFF00FF00FF00FF00) >> 8) | ((value & 0x00FF00FF00FF00FF) << 8); // swap bytes
        value = ((value & 0xFFFF0000FFFF0000) >> 16) | ((value & 0x0000FFFF0000FFFF) << 16); // swap 2-byte long pairs
        return (value >> 32) | (value << 32); // swap 4-byte long pairs
    }

    /// @dev Same as {reverseBytes32} but optimized for 32-bit values.
    function reverseBytes4(bytes4 value) internal pure returns (bytes4) {
        value = ((value & 0xFF00FF00) >> 8) | ((value & 0x00FF00FF) << 8); // swap bytes
        return (value >> 16) | (value << 16); // swap 2-byte long pairs
    }

    /// @dev Same as {reverseBytes32} but optimized for 16-bit values.
    function reverseBytes2(bytes2 value) internal pure returns (bytes2) {
        return (value >> 8) | (value << 8);
    }

    /**
     * @dev Counts the number of leading zero bits a bytes array. Returns `8 * buffer.length`
     * if the buffer is all zeros.
     */
    function clz(bytes memory buffer) internal pure returns (uint64) {
        for (uint64 i = 0; i < buffer.length; i += 32) {
            bytes32 chunk = _unsafeReadBytesOffset(buffer, i);
            if (chunk != bytes32(0)) {
                return min(8 * i + clz64(uint64(uint256(chunk))), 8 * uint64(buffer.length));
            }
        }
        return 8 * uint64(buffer.length);
    }

    /**
     * @dev Reads a bytes32 from a bytes array without bounds checking.
     *
     * NOTE: making this function internal would mean it could be used with memory unsafe offset, and marking the
     * assembly block as such would prevent some optimizations.
     */
    function _unsafeReadBytesOffset(bytes memory buffer, uint64 offset) private pure returns (bytes32 value) {
        // Manual extraction without mload
        value = bytes32(
            (uint256(uint8(buffer[offset])) << 248) |
            (uint256(uint8(buffer[offset + 1])) << 240) |
            (uint256(uint8(buffer[offset + 2])) << 232) |
            (uint256(uint8(buffer[offset + 3])) << 224) |
            (uint256(uint8(buffer[offset + 4])) << 216) |
            (uint256(uint8(buffer[offset + 5])) << 208) |
            (uint256(uint8(buffer[offset + 6])) << 200) |
            (uint256(uint8(buffer[offset + 7])) << 192) |
            (uint256(uint8(buffer[offset + 8])) << 184) |
            (uint256(uint8(buffer[offset + 9])) << 176) |
            (uint256(uint8(buffer[offset + 10])) << 168) |
            (uint256(uint8(buffer[offset + 11])) << 160) |
            (uint256(uint8(buffer[offset + 12])) << 152) |
            (uint256(uint8(buffer[offset + 13])) << 144) |
            (uint256(uint8(buffer[offset + 14])) << 136) |
            (uint256(uint8(buffer[offset + 15])) << 128) |
            (uint256(uint8(buffer[offset + 16])) << 120) |
            (uint256(uint8(buffer[offset + 17])) << 112) |
            (uint256(uint8(buffer[offset + 18])) << 104) |
            (uint256(uint8(buffer[offset + 19])) << 96) |
            (uint256(uint8(buffer[offset + 20])) << 88) |
            (uint256(uint8(buffer[offset + 21])) << 80) |
            (uint256(uint8(buffer[offset + 22])) << 72) |
            (uint256(uint8(buffer[offset + 23])) << 64) |
            (uint256(uint8(buffer[offset + 24])) << 56) |
            (uint256(uint8(buffer[offset + 25])) << 48) |
            (uint256(uint8(buffer[offset + 26])) << 40) |
            (uint256(uint8(buffer[offset + 27])) << 32) |
            (uint256(uint8(buffer[offset + 28])) << 24) |
            (uint256(uint8(buffer[offset + 29])) << 16) |
            (uint256(uint8(buffer[offset + 30])) << 8) |
            uint256(uint8(buffer[offset + 31]))
        );
    }

    // Helper: min for uint64
    function min(uint64 a, uint64 b) private pure returns (uint64) {
        return a < b ? a : b;
    }

    // Helper: saturatingAdd for uint64
    function saturatingAdd(uint64 a, uint64 b) private pure returns (uint64) {
        unchecked {
            uint64 c = a + b;
            if (c < a) return type(uint64).max;
            return c;
        }
    }

    // Helper: count leading zeros for uint64
    function clz64(uint64 x) private pure returns (uint64) {
        if (x == 0) return 64;
        uint64 n = 0;
        if (x <= 0x00000000FFFFFFFF) { n += 32; x <<= 32; }
        if (x <= 0x0000FFFFFFFFFFFF) { n += 16; x <<= 16; }
        if (x <= 0x00FFFFFFFFFFFFFF) { n += 8; x <<= 8; }
        if (x <= 0x0FFFFFFFFFFFFFFF) { n += 4; x <<= 4; }
        if (x <= 0x3FFFFFFFFFFFFFFF) { n += 2; x <<= 2; }
        if (x <= 0x7FFFFFFFFFFFFFFF) { n += 1; }
        return n;
    }
}