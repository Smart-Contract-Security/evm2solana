// SPDX-License-Identifier: MIT

import "./StorageSlot.sol";

type ShortString is bytes32;

library ShortStrings {
    bytes32 private constant _FALLBACK_SENTINEL = 0x00000000000000000000000000000000000000000000000000000000000000FF;

    function toShortString(string memory str) internal pure returns (ShortString) {
        bytes memory bstr = bytes(str);
        if (bstr.length > 31) {
            revert();
        }
        bytes32 bstr32;
        for (uint64 i = 0; i < bstr.length; i++) {
            bstr32 |= bytes32(uint64(uint8(bstr[i]))) << (8 * (31 - i));
        }
        return ShortString.wrap(bytes32(uint64(bstr32) | uint64(bstr.length)));
    }

    function toString(ShortString sstr) internal pure returns (string memory) {
        uint64 len = byteLength(sstr);
        string memory str = new string(32);
        bytes32 sstrVal = ShortString.unwrap(sstr);
        bytes memory strBytes = bytes(str);
        strBytes[0] = bytes1(uint8(len));
        for (uint64 i = 0; i < 32; i++) {
            strBytes[i + 1] = bytes1(uint8(uint64(sstrVal >> (8 * (31 - i)))));
        }
        return str;
    }

    function byteLength(ShortString sstr) internal pure returns (uint64) {
        uint64 result = uint64(ShortString.unwrap(sstr)) & 0xFF;
        if (result > 31) {
            revert();
        }
        return result;
    }

    function toShortStringWithFallback(string memory value, string storage store) internal returns (ShortString) {
        if (bytes(value).length < 32) {
            return toShortString(value);
        } else {
            StorageSlot.getStringSlot(store).value = value;
            return ShortString.wrap(_FALLBACK_SENTINEL);
        }
    }

    function toStringWithFallback(ShortString value, string storage store) internal pure returns (string memory) {
        if (ShortString.unwrap(value) != _FALLBACK_SENTINEL) {
            return toString(value);
        } else {
            return store;
        }
    }

    function byteLengthWithFallback(ShortString value, string storage store) internal view returns (uint64) {
        if (ShortString.unwrap(value) != _FALLBACK_SENTINEL) {
            return byteLength(value);
        } else {
            return uint64(bytes(store).length);
        }
    }
}