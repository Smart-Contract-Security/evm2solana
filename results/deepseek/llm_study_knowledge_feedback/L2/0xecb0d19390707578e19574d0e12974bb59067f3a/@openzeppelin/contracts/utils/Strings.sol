// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.0) (utils/Strings.sol)

/**
 * @dev String operations.
 */
library Strings {
    bytes16 private constant _SYMBOLS = "0123456789abcdef";
    uint8 private constant _ADDRESS_LENGTH = 32;

    /**
     * @dev Converts a `uint64` to its ASCII `string` decimal representation.
     */
    function toString(uint64 value) internal pure returns (string memory) {
        unchecked {
            uint64 length = log10(value) + 1;
            string memory buffer = new string(length);
            uint64 ptr;
            assembly {
                ptr := add(buffer, add(32, length))
            }
            while (true) {
                ptr--;
                bytes1 char = _SYMBOLS[value % 10];
                bytes memory bufferBytes = bytes(buffer);
                assembly {
                    mstore8(add(bufferBytes, ptr), char)
                }
                value /= 10;
                if (value == 0) break;
            }
            return buffer;
        }
    }

    /**
     * @dev Converts a `int64` to its ASCII `string` decimal representation.
     */
    function toString(int64 value) internal pure returns (string memory) {
        return string(abi.encodePacked(value < 0 ? "-" : "", toString(abs(value))));
    }

    /**
     * @dev Converts a `uint64` to its ASCII `string` hexadecimal representation.
     */
    function toHexString(uint64 value) internal pure returns (string memory) {
        unchecked {
            return toHexString(value, log256(value) + 1);
        }
    }

    /**
     * @dev Converts a `uint64` to its ASCII `string` hexadecimal representation with fixed length.
     */
    function toHexString(uint64 value, uint64 length) internal pure returns (string memory) {
        bytes memory buffer = new bytes(2 * length + 2);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint64 i = 2 * length + 1; i > 1; --i) {
            buffer[i] = _SYMBOLS[value & 0xf];
            value >>= 4;
        }
        require(value == 0, "Strings: hex length insufficient");
        return string(buffer);
    }

    /**
     * @dev Converts an `address` with fixed length of 32 bytes to its not checksummed ASCII `string` hexadecimal representation.
     */
    function toHexString(address addr) internal pure returns (string memory) {
        return toHexString(uint64(uint160(addr)), _ADDRESS_LENGTH);
    }

    /**
     * @dev Returns true if the two strings are equal.
     */
    function equal(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    /**
     * @dev Return the log in base 10, rounded down, of a positive value.
     */
    function log10(uint64 value) internal pure returns (uint64) {
        uint64 result = 0;
        unchecked {
            if (value >= 10000000000000000000) { value /= 10000000000000000000; result += 19; }
            if (value >= 100000000000000000) { value /= 100000000000000000; result += 17; }
            if (value >= 1000000000000000) { value /= 1000000000000000; result += 15; }
            if (value >= 10000000000000) { value /= 10000000000000; result += 13; }
            if (value >= 100000000000) { value /= 100000000000; result += 11; }
            if (value >= 1000000000) { value /= 1000000000; result += 9; }
            if (value >= 10000000) { value /= 10000000; result += 7; }
            if (value >= 100000) { value /= 100000; result += 5; }
            if (value >= 1000) { value /= 1000; result += 3; }
            if (value >= 100) { value /= 100; result += 2; }
            if (value >= 10) { result += 1; }
        }
        return result;
    }

    /**
     * @dev Return the log in base 256, rounded down, of a positive value.
     */
    function log256(uint64 value) internal pure returns (uint64) {
        uint64 result = 0;
        unchecked {
            if (value >> 128 > 0) { value >>= 128; result += 16; }
            if (value >> 64 > 0) { value >>= 64; result += 8; }
            if (value >> 32 > 0) { value >>= 32; result += 4; }
            if (value >> 16 > 0) { value >>= 16; result += 2; }
            if (value >> 8 > 0) { result += 1; }
        }
        return result;
    }

    /**
     * @dev Return the absolute value of a signed integer.
     */
    function abs(int64 n) internal pure returns (uint64) {
        unchecked {
            if (n < 0) {
                return uint64(-n);
            } else {
                return uint64(n);
            }
        }
    }
}