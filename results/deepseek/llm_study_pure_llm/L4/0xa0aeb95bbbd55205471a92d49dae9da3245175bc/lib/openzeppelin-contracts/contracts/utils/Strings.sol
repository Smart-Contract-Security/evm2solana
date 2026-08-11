// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library Strings {
    bytes16 private constant HEX_DIGITS = "0123456789abcdef";
    uint8 private constant ADDRESS_LENGTH = 20;

    error StringsInsufficientHexLength(uint256 value, uint256 length);

    function toString(uint256 value) internal pure returns (string memory) {
        unchecked {
            uint256 length = log10(value) + 1;
            string memory buffer = new string(length);
            uint256 ptr;
            assembly {
                ptr := add(buffer, add(32, length))
            }
            while (true) {
                ptr--;
                assembly {
                    mstore8(ptr, byte(mod(value, 10), HEX_DIGITS))
                }
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
            return toString(uint256(value));
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
            revert StringsInsufficientHexLength(value, length);
        }
        return string(buffer);
    }

    function toHexString(address addr) internal pure returns (string memory) {
        return toHexString(uint256(uint160(addr)), ADDRESS_LENGTH);
    }

    function toChecksumHexString(address addr) internal pure returns (string memory) {
        bytes memory buffer = bytes(toHexString(addr));

        uint256 hashValue;
        assembly {
            hashValue := shr(96, keccak256(add(buffer, 0x22), 40))
        }

        for (uint256 i = 41; i > 1; --i) {
            if (hashValue & 0xf > 7 && uint8(buffer[i]) > 96) {
                buffer[i] ^= 0x20;
            }
            hashValue >>= 4;
        }
        return string(buffer);
    }

    function equal(string memory a, string memory b) internal pure returns (bool) {
        return bytes(a).length == bytes(b).length && keccak256(bytes(a)) == keccak256(bytes(b));
    }

    // Math helpers (inlined to avoid external dependencies)
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
        if (value >= 0x100000000000000000000000000000000) {
            value >>= 128;
            result += 16;
        }
        if (value >= 0x10000000000000000) {
            value >>= 64;
            result += 8;
        }
        if (value >= 0x100000000) {
            value >>= 32;
            result += 4;
        }
        if (value >= 0x10000) {
            value >>= 16;
            result += 2;
        }
        if (value >= 0x100) {
            result += 1;
        }
        return result;
    }

    function abs(int256 value) internal pure returns (uint256) {
        return value < 0 ? uint256(-value) : uint256(value);
    }
}