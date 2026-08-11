// SPDX-License-Identifier: MIT

import {StorageSlot} from "./StorageSlot.sol";

type ShortString is bytes32;

library ShortStrings {
    bytes32 private constant FALLBACK_SENTINEL = 0x00000000000000000000000000000000000000000000000000000000000000FF;

    function toShortString(string memory str) internal pure returns (ShortString) {
        bytes memory bstr = bytes(str);
        if (bstr.length > 31) {
            revert("StringTooLong");
        }
        uint64 len = uint64(bstr.length);
        bytes32 bstr32;
        for (uint64 i = 0; i < 32; i++) {
            if (i < len) {
                bstr32 |= bytes32(uint64(uint8(bstr[i]))) << (uint64(31 - i) * 8);
            }
        }
        return ShortString.wrap(bytes32(uint64(bstr32) | len));
    }

    function toString(ShortString sstr) internal pure returns (string memory) {
        uint64 len = byteLength(sstr);
        string memory str = new string(32);
        bytes memory strBytes = bytes(str);
        for (uint64 i = 0; i < 32; i++) {
            strBytes[i] = 0;
        }
        bytes32 raw = ShortString.unwrap(sstr);
        for (uint64 i = 0; i < len; i++) {
            strBytes[i] = raw[i];
        }
        return str;
    }

    function byteLength(ShortString sstr) internal pure returns (uint64) {
        bytes32 raw = ShortString.unwrap(sstr);
        uint64 result = uint64(uint8(raw[31])) & 0xFF;
        if (result > 31) {
            revert("InvalidShortString");
        }
        return result;
    }

    function toShortStringWithFallback(string memory value, string storage store) internal returns (ShortString) {
        if (bytes(value).length < 32) {
            return toShortString(value);
        } else {
            StorageSlot.getStringSlot(store).value = value;
            return ShortString.wrap(FALLBACK_SENTINEL);
        }
    }

    function toStringWithFallback(ShortString value, string storage store) internal pure returns (string memory) {
        if (ShortString.unwrap(value) != FALLBACK_SENTINEL) {
            return toString(value);
        } else {
            return store;
        }
    }

    function byteLengthWithFallback(ShortString value, string storage store) internal view returns (uint64) {
        if (ShortString.unwrap(value) != FALLBACK_SENTINEL) {
            return byteLength(value);
        } else {
            return uint64(bytes(store).length);
        }
    }
}