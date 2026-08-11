// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title SVG primitive helpers for RektPunk
library RektPunkSVG {
    bytes16 private constant HEX = "0123456789abcdef";

    /// @notice Convert bytes3 RGB to lowercase 6-char ASCII hex (no `#`)
    function toHex(bytes3 c) internal pure returns (string memory) {
        bytes memory out = new bytes(6);
        uint24 v = uint24(c);
        for (uint256 i = 0; i < 6; i++) {
            out[5 - i] = HEX[v & 0xf];
            v >>= 4;
        }
        return string(out);
    }

    /// @notice Convert a small uint (0-99) to ASCII decimal
    function u(uint256 n) internal pure returns (string memory) {
        if (n < 10) {
            bytes memory b = new bytes(1);
            b[0] = bytes1(uint8(48 + n));
            return string(b);
        }
        bytes memory b2 = new bytes(2);
        b2[0] = bytes1(uint8(48 + n / 10));
        b2[1] = bytes1(uint8(48 + (n % 10)));
        return string(b2);
    }

    /// @notice Build one `<rect>` element. Width/height are clamped to >=1.
    function rect(uint256 x, uint256 y, uint256 w, uint256 h, bytes3 color)
        internal
        pure
        returns (string memory)
    {
        return string(
            abi.encodePacked(
                '<rect x="', u(x),
                '" y="', u(y),
                '" width="', u(w),
                '" height="', u(h),
                '" fill="#', toHex(color),
                '"/>'
            )
        );
    }
}
