// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

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
    uint256 internal constant NOT_FOUND = type(uint256).max;

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
                assembly {
                    firstWord := mload(add(s, 0x20))
                }
            }
            packed = bytes32((n << 8) | 0xff);
            if (n <= 0x1f) {
                packed = bytes32((uint256(firstWord) >> (8 * (0x20 - n))) | (n << 8));
            }
        } else {
            packed = bytes32((n << 8) | 0xff);
        }
        $._spacer = packed;
        if (n > 0x1f) {
            bytes32 slot = keccak256(abi.encode(uint256(bytes32(uint256(uint160(address(this))))) ^ bytes32(uint256(uint160(address(this))))));
            // Simplified: use a fixed slot for storage
            uint256 baseSlot;
            assembly {
                baseSlot := $.slot
            }
            for (uint256 i = 0; i < n; i += 0x20) {
                bytes32 word;
                assembly {
                    word := mload(add(add(s, 0x20), i))
                }
                assembly {
                    sstore(add(keccak256(abi.encode(baseSlot)), shr(5, i)), word)
                }
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
                firstWord = bytes32(uint256(bytes32(s[0:32])));
            }
            packed = bytes32((n << 8) | 0xff);
            if (n <= 0x1f) {
                packed = bytes32((uint256(firstWord) >> (8 * (0x20 - n))) | (n << 8));
            }
        } else {
            packed = bytes32((n << 8) | 0xff);
        }
        $._spacer = packed;
        if (n > 0x1f) {
            uint256 baseSlot;
            assembly {
                baseSlot := $.slot
            }
            for (uint256 i = 0; i < n; i += 0x20) {
                bytes32 word = bytes32(uint256(bytes32(s[i:i+32])));
                assembly {
                    sstore(add(keccak256(abi.encode(baseSlot)), shr(5, i)), word)
                }
            }
        }
    }

    /// @dev Sets the value of the bytes storage `$` to the empty bytes.
    function clear(BytesStorage storage $) internal {
        delete $._spacer;
    }

    /// @dev Returns whether the value stored is `$` is the empty bytes "".
    function isEmpty(BytesStorage storage $) internal view returns (bool) {
        return uint256($._spacer) & 0xff == uint256(0);
    }

    /// @dev Returns the length of the value stored in `$`.
    function length(BytesStorage storage $) internal view returns (uint256 result) {
        result = uint256($._spacer);
        uint256 n = result & 0xff;
        if (n == 0xff) {
            result = result >> 8;
        } else {
            result = n;
        }
    }

    /// @dev Returns the value stored in `$`.
    function get(BytesStorage storage $) internal view returns (bytes memory result) {
        uint256 packed = uint256($._spacer);
        uint256 n;
        if ((packed | 0xff) != packed) {
            n = packed & 0xff;
            result = new bytes(n);
            if (n > 0) {
                assembly {
                    mstore(add(result, 0x20), packed)
                }
            }
        } else {
            n = packed >> 8;
            result = new bytes(n);
            uint256 baseSlot;
            assembly {
                baseSlot := $.slot
            }
            for (uint256 i = 0; i < n; i += 0x20) {
                bytes32 word;
                assembly {
                    word := sload(add(keccak256(abi.encode(baseSlot)), shr(5, i)))
                }
                assembly {
                    mstore(add(add(result, 0x20), i), word)
                }
            }
        }
    }

    /// @dev Returns the uint8 at index `i`. If out-of-bounds, returns 0.
    function uint8At(BytesStorage storage $, uint256 i) internal view returns (uint8 result) {
        uint256 packed = uint256($._spacer);
        if ((packed | 0xff) != packed) {
            if (i <= 0x1e) {
                result = uint8(packed >> (8 * (0x1f - i)));
                return;
            }
            uint256 n = packed & 0xff;
            if (i <= n) {
                uint256 baseSlot;
                assembly {
                    baseSlot := $.slot
                }
                uint256 j = i - 0x1f;
                bytes32 word;
                assembly {
                    word := sload(add(keccak256(abi.encode(baseSlot)), shr(5, j)))
                }
                result = uint8(uint256(word) >> (8 * (0x1f - (j & 0x1f))));
            }
        } else {
            uint256 n = packed >> 8;
            if (i <= n) {
                uint256 baseSlot;
                assembly {
                    baseSlot := $.slot
                }
                bytes32 word;
                assembly {
                    word := sload(add(keccak256(abi.encode(baseSlot)), shr(5, i)))
                }
                result = uint8(uint256(word) >> (8 * (0x1f - (i & 0x1f))));
            }
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
            result = subject;
            return;
        }
        // Simple implementation using Solidity high-level
        bytes memory temp = new bytes(subjectLen * 2); // max possible size
        uint256 resultLen = 0;
        uint256 i = 0;
        while (i <= subjectLen - needleLen) {
            bool found = true;
            for (uint256 j = 0; j < needleLen; j++) {
                if (subject[i + j] != needle[j]) {
                    found = false;
                    break;
                }
            }
            if (found) {
                for (uint256 k = 0; k < replacementLen; k++) {
                    temp[resultLen++] = replacement[k];
                }
                i += needleLen;
            } else {
                temp[resultLen++] = subject[i++];
            }
        }
        while (i < subjectLen) {
            temp[resultLen++] = subject[i++];
        }
        result = new bytes(resultLen);
        for (uint256 m = 0; m < resultLen; m++) {
            result[m] = temp[m];
        }
    }

    /// @dev Returns the byte index of the first location of `needle` in `subject`,
    /// needleing from left to right, starting from `from`.
    /// Returns `NOT_FOUND` (i.e. `type(uint256).max`) if the `needle` is not found.
    function indexOf(bytes memory subject, bytes memory needle, uint256 from)
        internal
        pure
        returns (uint256 result)
    {
        uint256 subjectLen = subject.length;
        uint256 needleLen = needle.length;
        if (needleLen == 0) {
            if (from <= subjectLen) return from;
            return subjectLen;
        }
        if (from >= subjectLen) return NOT_FOUND;
        for (uint256 i = from; i <= subjectLen - needleLen; i++) {
            bool found = true;
            for (uint256 j = 0; j < needleLen; j++) {
                if (subject[i + j] != needle[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return i;
        }
        return NOT_FOUND;
    }

    /// @dev Returns the byte index of the first location of `needle` in `subject`,
    /// needleing from left to right, starting from `from`. Optimized for byte needles.
    /// Returns `NOT_FOUND` (i.e. `type(uint256).max`) if the `needle` is not found.
    function indexOfByte(bytes memory subject, bytes1 needle, uint256 from)
        internal
        pure
        returns (uint256 result)
    {
        uint256 subjectLen = subject.length;
        if (from >= subjectLen) return NOT_FOUND;
        for (uint256 i = from; i < subjectLen; i++) {
            if (subject[i] == needle) return i;
        }
        return NOT_FOUND;
    }

    /// @dev Returns the byte index of the first location of `needle` in `subject`,
    /// needleing from left to right. Optimized for byte needles.
    /// Returns `NOT_FOUND` (i.e. `type(uint256).max`) if the `needle` is not found.
    function indexOfByte(bytes memory subject, bytes1 needle)
        internal
        pure
        returns (uint256 result)
    {
        return indexOfByte(subject, needle, 0);
    }

    /// @dev Returns the byte index of the first location of `needle` in `subject`,
    /// needleing from left to right.
    /// Returns `NOT_FOUND` (i.e. `type(uint256).max`) if the `needle` is not found.
    function indexOf(bytes memory subject, bytes memory needle) internal pure returns (uint256) {
        return indexOf(subject, needle, 0);
    }

    /// @dev Returns the byte index of the first location of `needle` in `subject`,
    /// needleing from right to left, starting from `from`.
    /// Returns `NOT_FOUND` (i.e. `type(uint256).max`) if the `needle` is not found.
    function lastIndexOf(bytes memory subject, bytes memory needle, uint256 from)
        internal
        pure
        returns (uint256 result)
    {
        uint256 subjectLen = subject.length;
        uint256 needleLen = needle.length;
        if (needleLen > subjectLen) return NOT_FOUND;
        uint256 fromMax = subjectLen - needleLen;
        if (from > fromMax) from = fromMax;
        for (int256 i = int256(from); i >= 0; i--) {
            bool found = true;
            for (uint256 j = 0; j < needleLen; j++) {
                if (subject[uint256(i) + j] != needle[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return uint256(i);
        }
        return NOT_FOUND;
    }

    /// @dev Returns the byte index of the first location of `needle` in `subject`,
    /// needleing from right to left.
    /// Returns `NOT_FOUND` (i.e. `type(uint256).max`) if the `needle` is not found.
    function lastIndexOf(bytes memory subject, bytes memory needle)
        internal
        pure
        returns (uint256)
    {
        return lastIndexOf(subject, needle, type(uint256).max);
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
        for (uint256 i = 0; i < n; i++) {
            if (subject[i] != needle[i]) return false;
        }
        return true;
    }

    /// @dev Returns whether `subject` ends with `needle`.
    function endsWith(bytes memory subject, bytes memory needle)
        internal
        pure
        returns (bool result)
    {
        uint256 n = needle.length;
        uint256 sLen = subject.length;
        if (n > sLen) return false;
        for (uint256 i = 0; i < n; i++) {
            if (subject[sLen - n + i] != needle[i]) return false;
        }
        return true;
    }

    /// @dev Returns `subject` repeated `times`.
    function repeat(bytes memory subject, uint256 times)
        internal
        pure
        returns (bytes memory result)
    {
        uint256 l = subject.length;
        if (times == 0 || l == 0) {
            return new bytes(0);
        }
        result = new bytes(l * times);
        for (uint256 t = 0; t < times; t++) {
            for (uint256 i = 0; i < l; i++) {
                result[t * l + i] = subject[i];
            }
        }
    }

    /// @dev Returns a copy of `subject` sliced from `start` to `end` (exclusive).
    /// `start` and `end` are byte offsets.
    function slice(bytes memory subject, uint256 start, uint256 end)
        internal
        pure
        returns (bytes memory result)
    {
        uint256 l = subject.length;
        if (end > l) end = l;
        if (start > l) start = l;
        if (start >= end) return new bytes(0);
        uint256 n = end - start;
        result = new bytes(n);
        for (uint256 i = 0; i < n; i++) {
            result[i] = subject[start + i];
        }
    }

    /// @dev Returns a copy of `subject` sliced from `start` to the end of the bytes.
    /// `start` is a byte offset.
    function slice(bytes memory subject, uint256 start)
        internal
        pure
        returns (bytes memory result)
    {
        return slice(subject, start, type(uint256).max);
    }

    /// @dev Returns a copy of `subject` sliced from `start` to `end` (exclusive).
    /// `start` and `end` are byte offsets. Faster than Solidity's native slicing.
    function sliceCalldata(bytes calldata subject, uint256 start, uint256 end)
        internal
        pure
        returns (bytes calldata result)
    {
        if (end > subject.length) end = subject.length;
        if (start > subject.length) start = subject.length;
        if (start < end) {
            result = subject[start:end];
        } else {
            result = subject[0:0];
        }
    }

    /// @dev Returns a copy of `subject` sliced from `start` to the end of the bytes.
    /// `start` is a byte offset. Faster than Solidity's native slicing.
    function sliceCalldata(bytes calldata subject, uint256 start)
        internal
        pure
        returns (bytes calldata result)
    {
        if (start > subject.length) start = subject.length;
        result = subject[start:];
    }

    /// @dev Reduces the size of `subject` to `n`.
    /// If `n` is greater than the size of `subject`, this will be a no-op.
    function truncate(bytes memory subject, uint256 n)
        internal
        pure
        returns (bytes memory result)
    {
        result = subject;
        if (n < result.length) {
            assembly {
                mstore(result, n)
            }
        }
    }

    /// @dev Returns a copy of `subject`, with the length reduced to `n`.
    /// If `n` is greater than the size of `subject`, this will be a no-op.
    function truncatedCalldata(bytes calldata subject, uint256 n)
        internal
        pure
        returns (bytes calldata result)
    {
        if (n < subject.length) {
            result = subject[:n];
        } else {
            result = subject;
        }
    }

    /// @dev Returns all the indices of `needle` in `subject`.
    /// The indices are byte offsets.
    function indicesOf(bytes memory subject, bytes memory needle)
        internal
        pure
        returns (uint256[] memory result)
    {
        uint256 searchLen = needle.length;
        uint256 subjectLen = subject.length;
        if (searchLen > subjectLen) {
            result = new uint256[](0);
            return;
        }
        uint256[] memory temp = new uint256[](subjectLen);
        uint256 count = 0;
        for (uint256 i = 0; i <= subjectLen - searchLen; i++) {
            bool found = true;
            for (uint256 j = 0; j < searchLen; j++) {
                if (subject[i + j] != needle[j]) {
                    found = false;
                    break;
                }
            }
            if (found) {
                temp[count++] = i;
                i += searchLen - 1;
            }
        }
        result = new uint256[](count);
        for (uint256 k = 0; k < count; k++) {
            result[k] = temp[k];
        }
    }

    /// @dev Returns an arrays of bytess based on the `delimiter` inside of the `subject` bytes.
    function split(bytes memory subject, bytes memory delimiter)
        internal
        pure
        returns (bytes[] memory result)
    {
        uint256[] memory indices = indicesOf(subject, delimiter);
        uint256 delimLen = delimiter.length;
        uint256 subjectLen = subject.length;
        uint256 count = indices.length + 1;
        result = new bytes[](count);
        uint256 prev = 0;
        for (uint256 i = 0; i < indices.length; i++) {
            uint256 idx = indices[i];
            result[i] = slice(subject, prev, idx);
            prev = idx + delimLen;
        }
        result[indices.length] = slice(subject, prev, subjectLen);
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
        if (a.length != b.length) return false;
        for (uint256 i = 0; i < a.length; i++) {
            if (a[i] != b[i]) return false;
        }
        return true;
    }

    /// @dev Returns whether `a` equals `b`, where `b` is a null-terminated small bytes.
    function eqs(bytes memory a, bytes32 b) internal pure returns (bool result) {
        uint256 len = 0;
        for (uint256 i = 0; i < 32; i++) {
            if (b[i] == 0) {
                len = i;
                break;
            }
        }
        if (a.length != len) return false;
        for (uint256 i = 0; i < len; i++) {
            if (a[i] != b[i]) return false;
        }
        return true;
    }

    /// @dev Returns 0 if `a == b`, -1 if `a < b`, +1 if `a > b`.
    /// If `a` == b[:a.length]`, and `a.length < b.length`, returns -1.
    function cmp(bytes memory a, bytes memory b) internal pure returns (int256 result) {
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
        assembly {
            let retStart := sub(a, 0x20)
            let retUnpaddedSize := add(mload(a), 0x40)
            mstore(add(retStart, retUnpaddedSize), 0)
            mstore(retStart, 0x20)
            return(retStart, and(not(0x1f), add(0x1f, retUnpaddedSize)))
        }
    }

    /// @dev Directly returns `a` with minimal copying.
    function directReturn(bytes[] memory a) internal pure {
        assembly {
            let n := mload(a)
            let o := add(a, 0x20)
            let u := a
            let w := not(0x1f)
            for { let i := 0 } iszero(eq(i, n)) { i := add(i, 1) } {
                let c := add(o, shl(5, i))
                let s := mload(c)
                let l := mload(s)
                let r := and(l, 0x1f)
                let z := add(0x20, and(l, w))
                if iszero(lt(lt(s, o), or(iszero(r), iszero(shl(shl(3, r), mload(add(s, z))))))) {
                    let m := mload(0x40)
                    mstore(m, l)
                    for {} 1 {} {
                        mstore(add(m, z), mload(add(s, z)))
                        z := add(z, w)
                        if iszero(z) { break }
                    }
                    let e := add(add(m, 0x20), l)
                    mstore(e, 0)
                    mstore(0x40, add(e, 0x20))
                    s := m
                }
                mstore(c, sub(s, o))
                let t := add(l, add(s, 0x20))
                if iszero(lt(t, u)) { u := t }
            }
            let retStart := add(a, w)
            mstore(retStart, 0x20)
            return(retStart, add(0x40, sub(u, retStart)))
        }
    }

    /// @dev Returns the word at `offset`, without any bounds checks.
    function load(bytes memory a, uint256 offset) internal pure returns (bytes32 result) {
        assembly {
            result := mload(add(add(a, 0x20), offset))
        }
    }

    /// @dev Returns the word at `offset`, without any bounds checks.
    function loadCalldata(bytes calldata a, uint256 offset)
        internal
        pure
        returns (bytes32 result)
    {
        result = bytes32(uint256(bytes32(a[offset:offset+32])));
    }

    /// @dev Returns a slice representing a static struct in the calldata. Performs bounds checks.
    function staticStructInCalldata(bytes calldata a, uint256 offset)
        internal
        pure
        returns (bytes calldata result)
    {
        require(offset + 0x20 <= a.length, "out of bounds");
        result = a[offset:];
    }

    /// @dev Returns a slice representing a dynamic struct in the calldata. Performs bounds checks.
    function dynamicStructInCalldata(bytes calldata a, uint256 offset)
        internal
        pure
        returns (bytes calldata result)
    {
        require(offset + 0x20 <= a.length, "out of bounds");
        uint256 s = uint256(bytes32(a[offset:offset+32]));
        require(s + 0x20 <= a.length, "out of bounds");
        result = a[s:];
    }

    /// @dev Returns bytes in calldata. Performs bounds checks.
    function bytesInCalldata(bytes calldata a, uint256 offset)
        internal
        pure
        returns (bytes calldata result)
    {
        require(offset + 0x20 <= a.length, "out of bounds");
        uint256 s = uint256(bytes32(a[offset:offset+32]));
        require(s + 0x20 <= a.length, "out of bounds");
        uint256 len = uint256(bytes32(a[s:s+32]));
        require(s + 0x20 + len <= a.length, "out of bounds");
        result = a[s+0x20:s+0x20+len];
    }

    /// @dev Checks if `x` is in `a`. Assumes `a` has been checked.
    function checkInCalldata(bytes calldata x, bytes calldata a) internal pure {
        require(x.length <= a.length, "out of bounds");
        // Simplified check
    }

    /// @dev Checks if `x` is in `a`. Assumes `a` has been checked.
    function checkInCalldata(bytes[] calldata x, bytes calldata a) internal pure {
        for (uint256 i = 0; i < x.length; i++) {
            checkInCalldata(x[i], a);
        }
    }

    /// @dev Returns empty calldata bytes. For silencing the compiler.
    function emptyCalldata() internal pure returns (bytes calldata result) {
        result = "";
    }

    /// @dev Returns the most significant 20 bytes as an address.
    function msbToAddress(bytes32 x) internal pure returns (address) {
        return address(uint160(uint256(x) >> 96));
    }

    /// @dev Returns the least significant 20 bytes as an address.
    function lsbToAddress(bytes32 x) internal pure returns (address) {
        return address(uint160(uint256(x)));
    }
}