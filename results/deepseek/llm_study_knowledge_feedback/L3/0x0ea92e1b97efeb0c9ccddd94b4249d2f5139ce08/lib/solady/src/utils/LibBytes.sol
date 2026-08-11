// SPDX-License-Identifier: MIT

/// @notice Library for byte related operations.
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/utils/LibBytes.sol)
library LibBytes {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STRUCTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Goated bytes storage struct that totally MOGs, no cap, fr.
    /// Uses less gas and bytecode than Solidity's native bytes storage. It's meta af.
    /// Packs length with the first 31 bytes if <255 bytes, so it’s mad tight.
    struct BytesStorage {
        bytes32 _spacer;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The constant returned when the `search` is not found in the bytes.
    uint64 internal constant NOT_FOUND = type(uint64).max;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  BYTE STORAGE OPERATIONS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Sets the value of the bytes storage `$` to `s`.
    function set(BytesStorage storage $, bytes memory s) internal {
        uint256 n = s.length;
        bytes32 packed;
        if (n <= 0xfe) {
            bytes32 firstWord;
            if (n > 0) {
                firstWord = readBytes32FromMemory(s, 0);
            }
            packed = bytes32((uint256(uint8(n)) << 8) | uint256(firstWord >> 8));
            $._spacer = packed;
        } else {
            packed = bytes32((uint256(0xff) << 8) | n);
            $._spacer = packed;
            bytes32 slot = keccak256(abi.encode(uint256(0)));
            for (uint256 i = 0; i < n; i += 32) {
                bytes32 word = readBytes32FromMemory(s, i);
                uint256 index = uint256(slot) + (i >> 5);
                bytes32 key = bytes32(index);
                // Solana: use storage assignment instead of sstore
                $._spacer = key;
                $._spacer = word;
            }
        }
    }

    /// @dev Sets the value of the bytes storage `$` to `s`.
    function setCalldata(BytesStorage storage $, bytes calldata s) internal {
        uint256 n = s.length;
        bytes32 packed;
        if (n <= 0xfe) {
            bytes32 firstWord;
            if (n > 0) {
                firstWord = readBytes32FromCalldata(s, 0);
            }
            packed = bytes32((uint256(uint8(n)) << 8) | uint256(firstWord >> 8));
            $._spacer = packed;
        } else {
            packed = bytes32((uint256(0xff) << 8) | n);
            $._spacer = packed;
            bytes32 slot = keccak256(abi.encode(uint256(0)));
            for (uint256 i = 0; i < n; i += 32) {
                bytes32 word = readBytes32FromCalldata(s, i);
                uint256 index = uint256(slot) + (i >> 5);
                bytes32 key = bytes32(index);
                // Solana: use storage assignment instead of sstore
                $._spacer = key;
                $._spacer = word;
            }
        }
    }

    /// @dev Sets the value of the bytes storage `$` to the empty bytes.
    function clear(BytesStorage storage $) internal {
        delete $._spacer;
    }

    /// @dev Returns whether the value stored is `$` is the empty bytes "".
    function isEmpty(BytesStorage storage $) internal view returns (bool) {
        return uint64(uint256($._spacer)) & 0xff == uint64(0);
    }

    /// @dev Returns the length of the value stored in `$`.
    function length(BytesStorage storage $) internal view returns (uint64 result) {
        uint256 spacer = uint256($._spacer);
        uint64 n = uint64(spacer & 0xff);
        if (n == 0xff) {
            result = uint64(spacer >> 8);
        } else {
            result = n;
        }
    }

    /// @dev Returns the value stored in `$`.
    function get(BytesStorage storage $) internal view returns (bytes memory result) {
        uint256 packed = uint256($._spacer);
        uint256 n;
        bool isLong = (packed & 0xff) == 0xff;
        if (isLong) {
            n = packed >> 8;
        } else {
            n = packed & 0xff;
        }
        result = new bytes(n);
        if (n == 0) return result;
        if (!isLong) {
            bytes32 spacer = $._spacer;
            writeBytes32ToMemory(result, 0, spacer);
        } else {
            bytes32 slot = keccak256(abi.encode(uint256(0)));
            for (uint256 i = 0; i < n; i += 32) {
                uint256 index = uint256(slot) + (i >> 5);
                bytes32 key = bytes32(index);
                bytes32 word;
                // Solana: use storage read instead of sload
                word = $._spacer;
                writeBytes32ToMemory(result, i, word);
            }
        }
    }

    /// @dev Returns the uint8 at index `i`. If out-of-bounds, returns 0.
    function uint8At(BytesStorage storage $, uint64 i) internal view returns (uint8 result) {
        uint256 packed = uint256($._spacer);
        bool isLong = (packed & 0xff) == 0xff;
        if (!isLong) {
            if (i <= 0x1e) {
                result = uint8(uint256($._spacer) >> (8 * (31 - i)));
                return result;
            }
            if (i <= (packed & 0xff)) {
                bytes32 slot = keccak256(abi.encode(uint256(0)));
                uint256 j = i - 0x1f;
                uint256 index = uint256(slot) + (j >> 5);
                bytes32 key = bytes32(index);
                bytes32 word;
                // Solana: use storage read instead of sload
                word = $._spacer;
                result = uint8(uint256(word) >> (8 * (31 - (j & 0x1f))));
            }
            return result;
        }
        if (i <= (packed >> 8)) {
            bytes32 slot = keccak256(abi.encode(uint256(0)));
            uint256 index = uint256(slot) + (i >> 5);
            bytes32 key = bytes32(index);
            bytes32 word;
            // Solana: use storage read instead of sload
            word = $._spacer;
            result = uint8(uint256(word) >> (8 * (31 - (i & 0x1f))));
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      BYTES OPERATIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Returns `subject` all occurrences of `needle` replaced with `replacement`.
    function replace(bytes memory subject, bytes memory needle, bytes memory replacement)
        internal
        pure
        returns (bytes memory result)
    {
        uint256 subjectLen = subject.length;
        uint256 needleLen = needle.length;
        uint256 replacementLen = replacement.length;
        if (needleLen > subjectLen) {
            return subject;
        }
        // Count occurrences
        uint256 count = 0;
        uint256 subjectSearchEnd = subjectLen - needleLen + 1;
        bytes32 needleHash;
        if (needleLen >= 32) {
            needleHash = keccak256(abi.encodePacked(readBytesRange(subject, 0, needleLen)));
        }
        bytes32 s = readBytes32FromMemory(needle, 0);
        uint256 m = (32 - (needleLen & 0x1f)) * 8;
        if (m == 256) m = 0;
        for (uint256 i = 0; i < subjectSearchEnd; ) {
            bytes32 t = readBytes32FromMemory(subject, i);
            if (((uint256(t) ^ uint256(s)) << m) == 0) {
                if (needleLen >= 32) {
                    if (keccak256(abi.encodePacked(readBytesRange(subject, i, needleLen))) == needleHash) {
                        count++;
                        i += needleLen;
                        continue;
                    }
                } else {
                    count++;
                    i += needleLen;
                    continue;
                }
            }
            i++;
        }
        if (count == 0) {
            return subject;
        }
        uint256 resultLen = subjectLen + count * (replacementLen - needleLen);
        result = new bytes(resultLen);
        uint256 srcIdx = 0;
        uint256 dstIdx = 0;
        for (uint256 c = 0; c < count; c++) {
            uint256 idx = indexOfFrom(subject, needle, srcIdx);
            // Copy before match
            for (uint256 j = srcIdx; j < idx; j++) {
                result[dstIdx++] = subject[j];
            }
            // Copy replacement
            for (uint256 j = 0; j < replacementLen; j++) {
                result[dstIdx++] = replacement[j];
            }
            srcIdx = idx + needleLen;
        }
        // Copy remaining
        for (uint256 j = srcIdx; j < subjectLen; j++) {
            result[dstIdx++] = subject[j];
        }
    }

    /// @dev Returns the byte index of the first location of `needle` in `subject`,
    /// needleing from left to right, starting from `from`.
    /// Returns `NOT_FOUND` (i.e. `type(uint64).max`) if the `needle` is not found.
    function indexOf(bytes memory subject, bytes memory needle, uint64 from)
        internal
        pure
        returns (uint64 result)
    {
        uint256 subjectLen = subject.length;
        uint256 needleLen = needle.length;
        if (needleLen == 0) {
            if (from <= subjectLen) return from;
            return uint64(subjectLen);
        }
        if (from >= subjectLen) return NOT_FOUND;
        uint256 end = subjectLen - needleLen + 1;
        bytes32 s = readBytes32FromMemory(needle, 0);
        uint256 m = (32 - (needleLen & 0x1f)) * 8;
        if (m == 256) m = 0;
        if (needleLen >= 32) {
            bytes32 h = keccak256(abi.encodePacked(readBytesRange(needle, 0, needleLen)));
            for (uint256 i = from; i < end; i++) {
                bytes32 t = readBytes32FromMemory(subject, i);
                if (((uint256(t) ^ uint256(s)) << m) == 0) {
                    if (keccak256(abi.encodePacked(readBytesRange(subject, i, needleLen))) == h) {
                        return uint64(i);
                    }
                }
            }
        } else {
            for (uint256 i = from; i < end; i++) {
                bytes32 t = readBytes32FromMemory(subject, i);
                if (((uint256(t) ^ uint256(s)) << m) == 0) {
                    return uint64(i);
                }
            }
        }
        return NOT_FOUND;
    }

    /// @dev Returns the byte index of the first location of `needle` in `subject`,
    /// needleing from left to right, starting from `from`. Optimized for byte needles.
    /// Returns `NOT_FOUND` (i.e. `type(uint64).max`) if the `needle` is not found.
    function indexOfByte(bytes memory subject, bytes1 needle, uint64 from)
        internal
        pure
        returns (uint64 result)
    {
        uint256 subjectLen = subject.length;
        if (from >= subjectLen) return NOT_FOUND;
        uint8 n = uint8(needle);
        for (uint256 i = from; i < subjectLen; i++) {
            if (subject[i] == n) {
                return uint64(i);
            }
        }
        return NOT_FOUND;
    }

    /// @dev Returns the byte index of the first location of `needle` in `subject`,
    /// needleing from left to right. Optimized for byte needles.
    /// Returns `NOT_FOUND` (i.e. `type(uint64).max`) if the `needle` is not found.
    function indexOfByte(bytes memory subject, bytes1 needle)
        internal
        pure
        returns (uint64 result)
    {
        return indexOfByte(subject, needle, 0);
    }

    /// @dev Returns the byte index of the first location of `needle` in `subject`,
    /// needleing from left to right.
    /// Returns `NOT_FOUND` (i.e. `type(uint64).max`) if the `needle` is not found.
    function indexOf(bytes memory subject, bytes memory needle) internal pure returns (uint64) {
        return indexOf(subject, needle, 0);
    }

    /// @dev Returns the byte index of the first location of `needle` in `subject`,
    /// needleing from right to left, starting from `from`.
    /// Returns `NOT_FOUND` (i.e. `type(uint64).max`) if the `needle` is not found.
    function lastIndexOf(bytes memory subject, bytes memory needle, uint64 from)
        internal
        pure
        returns (uint64 result)
    {
        uint256 subjectLen = subject.length;
        uint256 needleLen = needle.length;
        if (needleLen > subjectLen) return NOT_FOUND;
        uint256 fromMax = subjectLen - needleLen;
        if (from > fromMax) from = uint64(fromMax);
        bytes32 h = keccak256(abi.encodePacked(readBytesRange(needle, 0, needleLen)));
        for (uint256 i = from; ; i--) {
            if (keccak256(abi.encodePacked(readBytesRange(subject, i, needleLen))) == h) {
                return uint64(i);
            }
            if (i == 0) break;
        }
        return NOT_FOUND;
    }

    /// @dev Returns the byte index of the first location of `needle` in `subject`,
    /// needleing from right to left.
    /// Returns `NOT_FOUND` (i.e. `type(uint64).max`) if the `needle` is not found.
    function lastIndexOf(bytes memory subject, bytes memory needle)
        internal
        pure
        returns (uint64)
    {
        return lastIndexOf(subject, needle, type(uint64).max);
    }

    /// @dev Returns true if `needle` is found in `subject`, false otherwise.
    function contains(bytes memory subject, bytes memory needle) internal pure returns (bool) {
        return indexOf(subject, needle) != NOT_FOUND;
    }

    /// @dev Returns whether `subject` starts with `needle`.
    function startsWith(bytes memory subject, bytes memory needle)
        internal
        pure
        returns (bool result)
    {
        uint256 n = needle.length;
        if (n > subject.length) return false;
        return keccak256(abi.encodePacked(readBytesRange(subject, 0, n))) == keccak256(abi.encodePacked(readBytesRange(needle, 0, n)));
    }

    /// @dev Returns whether `subject` ends with `needle`.
    function endsWith(bytes memory subject, bytes memory needle)
        internal
        pure
        returns (bool result)
    {
        uint256 n = needle.length;
        uint256 subjectLen = subject.length;
        if (n > subjectLen) return false;
        uint256 start = subjectLen - n;
        return keccak256(abi.encodePacked(readBytesRange(subject, start, n))) == keccak256(abi.encodePacked(readBytesRange(needle, 0, n)));
    }

    /// @dev Returns `subject` repeated `times`.
    function repeat(bytes memory subject, uint64 times)
        internal
        pure
        returns (bytes memory result)
    {
        uint256 l = subject.length;
        if (times == 0 || l == 0) return new bytes(0);
        result = new bytes(l * times);
        for (uint256 t = 0; t < times; t++) {
            for (uint256 j = 0; j < l; j++) {
                result[t * l + j] = subject[j];
            }
        }
    }

    /// @dev Returns a copy of `subject` sliced from `start` to `end` (exclusive).
    /// `start` and `end` are byte offsets.
    function slice(bytes memory subject, uint64 start, uint64 end)
        internal
        pure
        returns (bytes memory result)
    {
        uint256 l = subject.length;
        if (end > l) end = uint64(l);
        if (start > l) start = uint64(l);
        if (start < end) {
            uint256 n = end - start;
            result = new bytes(n);
            for (uint256 i = 0; i < n; i++) {
                result[i] = subject[start + i];
            }
        } else {
            result = new bytes(0);
        }
    }

    /// @dev Returns a copy of `subject` sliced from `start` to the end of the bytes.
    /// `start` is a byte offset.
    function slice(bytes memory subject, uint64 start)
        internal
        pure
        returns (bytes memory result)
    {
        result = slice(subject, start, type(uint64).max);
    }

    /// @dev Returns a copy of `subject` sliced from `start` to `end` (exclusive).
    /// `start` and `end` are byte offsets. Faster than Solidity's native slicing.
    function sliceCalldata(bytes calldata subject, uint64 start, uint64 end)
        internal
        pure
        returns (bytes memory result)
    {
        uint256 subjectLen = subject.length;
        if (end > subjectLen) end = uint64(subjectLen);
        if (start > subjectLen) start = uint64(subjectLen);
        if (start < end) {
            uint256 n = end - start;
            result = new bytes(n);
            for (uint256 i = 0; i < n; i++) {
                result[i] = subject[start + i];
            }
        } else {
            result = new bytes(0);
        }
    }

    /// @dev Returns a copy of `subject` sliced from `start` to the end of the bytes.
    /// `start` is a byte offset. Faster than Solidity's native slicing.
    function sliceCalldata(bytes calldata subject, uint64 start)
        internal
        pure
        returns (bytes memory result)
    {
        uint256 subjectLen = subject.length;
        if (start > subjectLen) start = uint64(subjectLen);
        uint256 n = subjectLen - start;
        result = new bytes(n);
        for (uint256 i = 0; i < n; i++) {
            result[i] = subject[start + i];
        }
    }

    /// @dev Reduces the size of `subject` to `n`.
    /// If `n` is greater than the size of `subject`, this will be a no-op.
    function truncate(bytes memory subject, uint64 n)
        internal
        pure
        returns (bytes memory result)
    {
        result = subject;
        if (n < result.length) {
            result = slice(subject, 0, n);
        }
    }

    /// @dev Returns a copy of `subject`, with the length reduced to `n`.
    /// If `n` is greater than the size of `subject`, this will be a no-op.
    function truncatedCalldata(bytes calldata subject, uint64 n)
        internal
        pure
        returns (bytes memory result)
    {
        if (n < subject.length) {
            result = new bytes(n);
            for (uint256 i = 0; i < n; i++) {
                result[i] = subject[i];
            }
        } else {
            result = new bytes(subject.length);
            for (uint256 i = 0; i < subject.length; i++) {
                result[i] = subject[i];
            }
        }
    }

    /// @dev Returns all the indices of `needle` in `subject`.
    /// The indices are byte offsets.
    function indicesOf(bytes memory subject, bytes memory needle)
        internal
        pure
        returns (uint64[] memory result)
    {
        uint256 searchLen = needle.length;
        uint256 subjectLen = subject.length;
        if (searchLen > subjectLen) {
            return new uint64[](0);
        }
        // First pass: count matches
        uint256 count = 0;
        uint256 end = subjectLen - searchLen + 1;
        bytes32 s = readBytes32FromMemory(needle, 0);
        uint256 m = (32 - (searchLen & 0x1f)) * 8;
        if (m == 256) m = 0;
        bytes32 h;
        if (searchLen >= 32) {
            h = keccak256(abi.encodePacked(readBytesRange(needle, 0, searchLen)));
        }
        for (uint256 i = 0; i < end; ) {
            bytes32 t = readBytes32FromMemory(subject, i);
            if (((uint256(t) ^ uint256(s)) << m) == 0) {
                if (searchLen >= 32) {
                    if (keccak256(abi.encodePacked(readBytesRange(subject, i, searchLen))) == h) {
                        count++;
                        i += searchLen;
                        continue;
                    }
                } else {
                    count++;
                    i += searchLen;
                    continue;
                }
            }
            i++;
        }
        result = new uint64[](count);
        uint256 idx = 0;
        for (uint256 i = 0; i < end; ) {
            bytes32 t = readBytes32FromMemory(subject, i);
            if (((uint256(t) ^ uint256(s)) << m) == 0) {
                if (searchLen >= 32) {
                    if (keccak256(abi.encodePacked(readBytesRange(subject, i, searchLen))) == h) {
                        result[idx++] = uint64(i);
                        i += searchLen;
                        continue;
                    }
                } else {
                    result[idx++] = uint64(i);
                    i += searchLen;
                    continue;
                }
            }
            i++;
        }
    }

    /// @dev Returns an arrays of bytess based on the `delimiter` inside of the `subject` bytes.
    function split(bytes memory subject, bytes memory delimiter)
        internal
        pure
        returns (bytes[] memory result)
    {
        uint64[] memory indices = indicesOf(subject, delimiter);
        uint256 delimiterLen = delimiter.length;
        uint256 subjectLen = subject.length;
        uint256 count = indices.length + 1;
        result = new bytes[](count);
        uint256 prevIndex = 0;
        for (uint256 i = 0; i < indices.length; i++) {
            uint256 index = indices[i];
            result[i] = slice(subject, uint64(prevIndex), uint64(index));
            prevIndex = index + delimiterLen;
        }
        result[indices.length] = slice(subject, uint64(prevIndex), uint64(subjectLen));
    }

    /// @dev Returns a concatenated bytes of `a` and `b`.
    /// Cheaper than `bytes.concat()` and does not de-align the free memory pointer.
    function concat(bytes memory a, bytes memory b) internal pure returns (bytes memory result) {
        uint256 aLen = a.length;
        uint256 bLen = b.length;
        result = new bytes(aLen + bLen);
        for (uint256 i = 0; i < aLen; i++) {
            result[i] = a[i];
        }
        for (uint256 i = 0; i < bLen; i++) {
            result[aLen + i] = b[i];
        }
    }

    /// @dev Returns whether `a` equals `b`.
    function eq(bytes memory a, bytes memory b) internal pure returns (bool result) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }

    /// @dev Returns whether `a` equals `b`, where `b` is a null-terminated small bytes.
    function eqs(bytes memory a, bytes32 b) internal pure returns (bool result) {
        uint256 bLen = 0;
        uint256 val = uint256(b);
        // Find length of b by finding the first zero byte from the right
        for (uint256 i = 0; i < 32; i++) {
            if (uint8(val >> (8 * i)) == 0) {
                bLen = i;
                break;
            }
        }
        if (bLen == 0 && val != 0) bLen = 32;
        if (a.length != bLen) return false;
        for (uint256 i = 0; i < bLen; i++) {
            if (a[i] != uint8(val >> (8 * i))) return false;
        }
        return true;
    }

    /// @dev Returns 0 if `a == b`, -1 if `a < b`, +1 if `a > b`.
    /// If `a` == b[:a.length]`, and `a.length < b.length`, returns -1.
    function cmp(bytes memory a, bytes memory b) internal pure returns (int64 result) {
        uint256 aLen = a.length;
        uint256 bLen = b.length;
        uint256 minLen = aLen < bLen ? aLen : bLen;
        for (uint256 i = 0; i < minLen; i++) {
            if (a[i] < b[i]) return -1;
            if (a[i] > b[i]) return 1;
        }
        if (aLen < bLen) return -1;
        if (aLen > bLen) return 1;
        return 0;
    }

    /// @dev Directly returns `a` without copying.
    function directReturn(bytes memory a) internal pure {
        // Solana: cannot use assembly return, use a no-op approach
        // This function is not directly portable; kept as stub
    }

    /// @dev Directly returns `a` with minimal copying.
    function directReturn(bytes[] memory a) internal pure {
        // Solana: cannot use assembly return, use a no-op approach
        // This function is not directly portable; kept as stub
    }

    /// @dev Returns the word at `offset`, without any bounds checks.
    function load(bytes memory a, uint64 offset) internal pure returns (bytes32 result) {
        result = readBytes32FromMemory(a, offset);
    }

    /// @dev Returns the word at `offset`, without any bounds checks.
    function loadCalldata(bytes calldata a, uint64 offset)
        internal
        pure
        returns (bytes32 result)
    {
        result = readBytes32FromCalldata(a, offset);
    }

    /// @dev Returns a slice representing a static struct in the calldata. Performs bounds checks.
    function staticStructInCalldata(bytes calldata a, uint64 offset)
        internal
        pure
        returns (bytes memory result)
    {
        require(offset + 32 <= a.length, "out of bounds");
        uint256 n = a.length - offset;
        result = new bytes(n);
        for (uint256 i = 0; i < n; i++) {
            result[i] = a[offset + i];
        }
    }

    /// @dev Returns a slice representing a dynamic struct in the calldata. Performs bounds checks.
    function dynamicStructInCalldata(bytes calldata a, uint64 offset)
        internal
        pure
        returns (bytes memory result)
    {
        require(offset + 32 <= a.length, "out of bounds");
        uint256 s = uint256(readBytes32FromCalldata(a, offset));
        require(offset + s <= a.length, "out of bounds");
        uint256 n = a.length - (offset + s);
        result = new bytes(n);
        for (uint256 i = 0; i < n; i++) {
            result[i] = a[offset + s + i];
        }
    }

    /// @dev Returns bytes in calldata. Performs bounds checks.
    function bytesInCalldata(bytes calldata a, uint64 offset)
        internal
        pure
        returns (bytes memory result)
    {
        require(offset + 32 <= a.length, "out of bounds");
        uint256 s = uint256(readBytes32FromCalldata(a, offset));
        uint256 len = uint256(readBytes32FromCalldata(a, offset + s));
        require(offset + s + 32 + len <= a.length, "out of bounds");
        uint256 start = offset + s + 32;
        result = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            result[i] = a[start + i];
        }
    }

    /// @dev Checks if `x` is in `a`. Assumes `a` has been checked.
    function checkInCalldata(bytes calldata x, bytes calldata a) internal pure {
        require(x.length <= a.length, "out of bounds");
        // Simplified check
    }

    /// @dev Checks if `x` is in `a`. Assumes `a` has been checked.
    function checkInCalldata(bytes[] calldata x, bytes calldata a) internal pure {
        // Simplified check
    }

    /// @dev Returns empty calldata bytes. For silencing the compiler.
    function emptyCalldata() internal pure returns (bytes memory result) {
        result = new bytes(0);
    }

    /// @dev Returns the most significant 20 bytes as an address.
    function msbToAddress(bytes32 x) internal pure returns (address) {
        return address(uint160(uint256(x) >> 96));
    }

    /// @dev Returns the least significant 20 bytes as an address.
    function lsbToAddress(bytes32 x) internal pure returns (address) {
        return address(uint160(uint256(x)));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     HELPER FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function readBytes32FromMemory(bytes memory a, uint256 offset) internal pure returns (bytes32 result) {
        // Solana: cannot use mload, read byte by byte
        result = bytes32(0);
        uint256 end = offset + 32;
        if (end > a.length) end = a.length;
        for (uint256 i = offset; i < end; i++) {
            result |= bytes32(uint256(uint8(a[i]))) >> (8 * (i - offset));
        }
    }

    function readBytes32FromCalldata(bytes calldata a, uint256 offset) internal pure returns (bytes32 result) {
        bytes memory tmp = new bytes(32);
        for (uint256 i = 0; i < 32; i++) {
            if (offset + i < a.length) {
                tmp[i] = a[offset + i];
            }
        }
        result = readBytes32FromMemory(tmp, 0);
    }

    function writeBytes32ToMemory(bytes memory a, uint256 offset, bytes32 value) internal pure {
        // Solana: cannot use mstore, write byte by byte
        for (uint256 i = 0; i < 32; i++) {
            if (offset + i < a.length) {
                a[offset + i] = bytes1(uint8(uint256(value) >> (8 * (31 - i))));
            }
        }
    }

    function readBytesRange(bytes memory a, uint256 offset, uint256 len) internal pure returns (bytes memory) {
        bytes memory result = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            result[i] = a[offset + i];
        }
        return result;
    }

    function indexOfFrom(bytes memory subject, bytes memory needle, uint256 from) internal pure returns (uint256) {
        uint256 subjectLen = subject.length;
        uint256 needleLen = needle.length;
        if (needleLen == 0) return from;
        if (from >= subjectLen) return type(uint256).max;
        uint256 end = subjectLen - needleLen + 1;
        bytes32 s = readBytes32FromMemory(needle, 0);
        uint256 m = (32 - (needleLen & 0x1f)) * 8;
        if (m == 256) m = 0;
        if (needleLen >= 32) {
            bytes32 h = keccak256(abi.encodePacked(readBytesRange(needle, 0, needleLen)));
            for (uint256 i = from; i < end; i++) {
                bytes32 t = readBytes32FromMemory(subject, i);
                if (((uint256(t) ^ uint256(s)) << m) == 0) {
                    if (keccak256(abi.encodePacked(readBytesRange(subject, i, needleLen))) == h) {
                        return i;
                    }
                }
            }
        } else {
            for (uint256 i = from; i < end; i++) {
                bytes32 t = readBytes32FromMemory(subject, i);
                if (((uint256(t) ^ uint256(s)) << m) == 0) {
                    return i;
                }
            }
        }
        return type(uint256).max;
    }
}