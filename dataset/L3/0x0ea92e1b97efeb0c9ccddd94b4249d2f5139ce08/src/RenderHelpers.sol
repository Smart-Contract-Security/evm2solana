// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibString} from "solady/utils/LibString.sol";

/// @notice Tiny helpers shared by SVG and HTML renderers. All pure, all
/// view-only. Internal library — inlined where used, but only into the
/// two renderers (not the main contract).
library RenderHelpers {
    uint256 internal constant SCALE = 10000;

    function readU32(bytes memory data, uint256 offset) internal pure returns (uint256) {
        return (uint256(uint8(data[offset])) << 24)
             | (uint256(uint8(data[offset + 1])) << 16)
             | (uint256(uint8(data[offset + 2])) << 8)
             | uint256(uint8(data[offset + 3]));
    }

    function readU16(bytes memory data, uint256 offset) internal pure returns (uint256) {
        return (uint256(uint8(data[offset])) << 8) | uint256(uint8(data[offset + 1]));
    }

    function readLengthPrefixed(bytes memory data, uint256 off) internal pure returns (string memory) {
        uint8 len = uint8(data[off]);
        bytes memory out = new bytes(len);
        for (uint256 i; i < len; i++) out[i] = data[off + 1 + i];
        return string(out);
    }

    /// @dev v is scaled by 10000. Returns "5.9" / "0.04" / "205" with trailing zeros stripped.
    function fix(uint256 v) internal pure returns (string memory) {
        uint256 ip = v / SCALE;
        uint256 fp = v % SCALE;
        if (fp == 0) return LibString.toString(ip);
        uint256 digits = 4;
        while (digits > 1 && fp % 10 == 0) { fp /= 10; digits--; }
        string memory fs = LibString.toString(fp);
        while (bytes(fs).length < digits) fs = string.concat("0", fs);
        return string.concat(LibString.toString(ip), ".", fs);
    }

    function toHexColor(bytes4 c) internal pure returns (string memory) {
        bytes memory out = new bytes(9);
        out[0] = "#";
        for (uint256 i; i < 4; i++) {
            uint8 b = uint8(c[i]);
            out[1 + i * 2] = _nib(b >> 4);
            out[2 + i * 2] = _nib(b & 0xf);
        }
        return string(out);
    }

    function _nib(uint8 v) private pure returns (bytes1) {
        return v < 10 ? bytes1(uint8(0x30 + v)) : bytes1(uint8(0x57 + v));
    }

    function utf8Len(uint8 b) internal pure returns (uint256) {
        if (b < 0x80) return 1;
        if (b < 0xC0) return 1;
        if (b < 0xE0) return 2;
        if (b < 0xF0) return 3;
        return 4;
    }
}
