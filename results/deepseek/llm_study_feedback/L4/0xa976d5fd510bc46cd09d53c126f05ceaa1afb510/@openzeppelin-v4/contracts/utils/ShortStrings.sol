// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

type ShortString is bytes32;

library ShortStrings {
    bytes32 private constant _FALLBACK_SENTINEL = 0x00000000000000000000000000000000000000000000000000000000000000FF;

    function toShortString(string memory str) internal pure returns (ShortString) {
        bytes memory bstr = bytes(str);
        if (bstr.length > 31) {
            revert("StringTooLong");
        }
        bytes32 b32;
        for (uint i = 0; i < bstr.length; i++) {
            b32 |= bytes32(uint256(uint8(bstr[i]))) >> (i * 8);
        }
        return ShortString.wrap(bytes32(uint256(b32) | bstr.length));
    }

    function toString(ShortString sstr) internal pure returns (string memory) {
        uint256 len = byteLength(sstr);
        bytes memory b = new bytes(len);
        bytes32 val = ShortString.unwrap(sstr);
        for (uint i = 0; i < len; i++) {
            b[i] = bytes1(uint8(uint256(val) >> (i * 8)));
        }
        return string(b);
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
            bytes memory valueBytes = bytes(value);
            for (uint i = 0; i < valueBytes.length; i++) {
                store = string(abi.encodePacked(store, valueBytes[i]));
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