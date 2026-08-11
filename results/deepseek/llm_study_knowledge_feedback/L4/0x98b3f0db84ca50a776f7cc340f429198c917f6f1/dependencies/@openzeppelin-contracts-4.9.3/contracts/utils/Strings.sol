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
            bytes memory bufferBytes = bytes(buffer);
            uint64 ptr = length;
            while (true) {
                ptr--;
                bufferBytes[ptr] = _SYMBOLS[value % 10];
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
     * @dev Return the log in base 10 of a positive value rounded towards zero.
     */
    function log10(uint64 value) internal pure returns (uint64) {
        uint64 result = 0;
        unchecked {
            if (value >= 10**18) { value /= 10**18; result += 18; }
            if (value >= 10**9) { value /= 10**9; result += 9; }
            if (value >= 10**6) { value /= 10**6; result += 6; }
            if (value >= 10**3) { value /= 10**3; result += 3; }
            if (value >= 10**2) { value /= 10**2; result += 2; }
            if (value >= 10**1) { value /= 10**1; result += 1; }
        }
        return result;
    }

    /**
     * @dev Return the log in base 256 of a positive value rounded towards zero.
     */
    function log256(uint64 value) internal pure returns (uint64) {
        uint64 result = 0;
        unchecked {
            if (value >= 2**128) { value >>= 128; result += 16; }
            if (value >= 2**64) { value >>= 64; result += 8; }
            if (value >= 2**32) { value >>= 32; result += 4; }
            if (value >= 2**16) { value >>= 16; result += 2; }
            if (value >= 2**8) { value >>= 8; result += 1; }
        }
        return result;
    }

    /**
     * @dev Return the absolute value of a signed integer.
     */
    function abs(int64 value) internal pure returns (uint64) {
        unchecked {
            return value < 0 ? uint64(-value) : uint64(value);
        }
    }
}