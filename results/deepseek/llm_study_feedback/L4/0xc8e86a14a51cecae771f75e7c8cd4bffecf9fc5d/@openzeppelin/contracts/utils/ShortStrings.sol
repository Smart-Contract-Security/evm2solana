// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

type ShortString is bytes32;

library ShortStrings {
    bytes32 private constant _FALLBACK_SENTINEL = 0x00000000000000000000000000000000000000000000000000000000000000FF;

    error StringTooLong(string str);
    error InvalidShortString();

    function toShortString(string memory str) internal pure returns (ShortString) {
        bytes memory bstr = bytes(str);
        if (bstr.length > 31) {
            revert("StringTooLong");
        }
        bytes32 b32 = bytes32(bstr);
        return ShortString.wrap(bytes32(uint256(b32) | bstr.length));
    }

    function toString(ShortString sstr) internal pure returns (string memory) {
        uint256 len = byteLength(sstr);
        bytes memory b = new bytes(32);
        for (uint256 i = 0; i < 32; i++) {
            b[i] = bytes1(uint8(uint256(ShortString.unwrap(sstr)) >> (8 * (31 - i))));
        }
        bytes memory result = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            result[i] = b[i];
        }
        return string(result);
    }

    function byteLength(ShortString sstr) internal pure returns (uint256) {
        uint256 result = uint256(ShortString.unwrap(sstr)) & 0xFF;
        if (result > 31) {
            revert("InvalidShortString");
        }
        return result;
    }

    function toShortStringWithFallback(string memory value, string storage store) internal returns (ShortString) {
        if (bytes(value).length < 32) {
            return toShortString(value);
        } else {
            // Solang does not support assigning a memory string to a storage string directly.
            // Instead, we copy the bytes manually.
            bytes memory valueBytes = bytes(value);
            for (uint256 i = 0; i < valueBytes.length; i++) {
                store.push(valueBytes[i]);
            }
            return ShortString.wrap(_FALLBACK_SENTINEL);
        }
    }

    function toStringWithFallback(ShortString value, string storage store) internal view returns (string memory) {
        if (ShortString.unwrap(value) != _FALLBACK_SENTINEL) {
            return toString(value);
        } else {
            return store;
        }
    }

    function byteLengthWithFallback(ShortString value, string storage store) internal view returns (uint256) {
        if (ShortString.unwrap(value) != _FALLBACK_SENTINEL) {
            return byteLength(value);
        } else {
            return bytes(store).length;
        }
    }
}