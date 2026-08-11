// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

type ShortString is bytes32;

library ShortStrings {
    bytes32 private constant FALLBACK_SENTINEL = 0x00000000000000000000000000000000000000000000000000000000000000FF;

    function toShortString(string memory str) internal pure returns (ShortString) {
        bytes memory bstr = bytes(str);
        if (bstr.length > 0x1f) {
            revert("StringTooLong");
        }
        bytes32 b32;
        for (uint256 i = 0; i < bstr.length; i++) {
            b32 |= bytes32(uint256(uint8(bstr[i]))) >> (i * 8);
        }
        return ShortString.wrap(bytes32(uint256(b32) | bstr.length));
    }

    function toString(ShortString sstr) internal pure returns (string memory) {
        uint256 len = byteLength(sstr);
        string memory str = new string(len);
        bytes memory bstr = bytes(str);
        bytes32 raw = ShortString.unwrap(sstr);
        for (uint256 i = 0; i < len; i++) {
            bstr[i] = bytes1(uint8(uint256(raw) >> (i * 8)));
        }
        return str;
    }

    function byteLength(ShortString sstr) internal pure returns (uint256) {
        uint256 result = uint256(ShortString.unwrap(sstr)) & 0xFF;
        if (result > 0x1f) {
            revert("InvalidShortString");
        }
        return result;
    }

    function toShortStringWithFallback(string memory value, string storage store) internal returns (ShortString) {
        if (bytes(value).length < 0x20) {
            return toShortString(value);
        } else {
            // Solang does not support assigning a memory string to a storage string directly.
            // Instead, we copy the bytes manually.
            bytes memory valueBytes = bytes(value);
            bytes storage storeBytes = bytes(store);
            // Clear existing storage
            for (uint256 i = storeBytes.length; i > 0; i--) {
                storeBytes.pop();
            }
            // Push new bytes
            for (uint256 i = 0; i < valueBytes.length; i++) {
                storeBytes.push(valueBytes[i]);
            }
            return ShortString.wrap(FALLBACK_SENTINEL);
        }
    }

    function toStringWithFallback(ShortString value, string storage store) internal view returns (string memory) {
        if (ShortString.unwrap(value) != FALLBACK_SENTINEL) {
            return toString(value);
        } else {
            return store;
        }
    }

    function byteLengthWithFallback(ShortString value, string storage store) internal view returns (uint256) {
        if (ShortString.unwrap(value) != FALLBACK_SENTINEL) {
            return byteLength(value);
        } else {
            return bytes(store).length;
        }
    }
}