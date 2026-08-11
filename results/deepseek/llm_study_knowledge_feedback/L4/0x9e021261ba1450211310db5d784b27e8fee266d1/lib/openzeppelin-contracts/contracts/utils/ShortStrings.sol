// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.5.0) (utils/ShortStrings.sol)

type ShortString is bytes32;

library ShortStrings {
    bytes32 private constant FALLBACK_SENTINEL = 0x00000000000000000000000000000000000000000000000000000000000000FF;

    function toShortString(string memory str) internal pure returns (ShortString) {
        bytes memory bstr = bytes(str);
        if (bstr.length > 0x1f) {
            revert("StringTooLong");
        }
        uint64 len = uint64(bstr.length);
        bytes32 packed = bytes32(0);
        for (uint64 i = 0; i < len; i++) {
            packed |= bytes32(uint64(uint8(bstr[i]))) << (8 * (31 - i));
        }
        return ShortString.wrap(bytes32(uint64(packed) | len));
    }

    function toString(ShortString sstr) internal pure returns (string memory) {
        uint64 len = byteLength(sstr);
        bytes memory str = new bytes(len);
        bytes32 raw = ShortString.unwrap(sstr);
        for (uint64 i = 0; i < len; i++) {
            str[i] = bytes1(uint8(uint64(raw >> (8 * (31 - i)))));
        }
        return string(str);
    }

    function byteLength(ShortString sstr) internal pure returns (uint64) {
        uint64 result = uint64(ShortString.unwrap(sstr)) & 0xFF;
        if (result > 0x1f) {
            revert("InvalidShortString");
        }
        return result;
    }

    function toShortStringWithFallback(string memory value, string storage store) internal returns (ShortString) {
        if (bytes(value).length < 0x20) {
            return toShortString(value);
        } else {
            store = value;
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

    function byteLengthWithFallback(ShortString value, string storage store) internal view returns (uint64) {
        if (ShortString.unwrap(value) != FALLBACK_SENTINEL) {
            return byteLength(value);
        } else {
            return uint64(bytes(store).length);
        }
    }
}