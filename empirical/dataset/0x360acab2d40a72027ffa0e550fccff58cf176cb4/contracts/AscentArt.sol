// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {LibString} from "./solady/utils/LibString.sol";
import {Base64} from "./solady/utils/Base64.sol";

/// @title AscentArt
/// @notice Perspective neon path SVG for $ASCENT (green rails, purple horizontal rungs).
library AscentArt {
    using LibString for uint256;

    struct Palette {
        string green;
        string purple;
        string purpleDim;
    }

    function palette(bytes32 seed) internal pure returns (Palette memory p) {
        uint256 h = uint256(seed) % 360;
        p.green = _hsl(125 + h, 100, 58);
        p.purple = _hsl(285 + h, 85, 68);
        p.purpleDim = _hsl(285 + h, 70, 45);
    }

    function svg(bytes32 seed, uint256 tokenId) internal pure returns (string memory) {
        Palette memory p = palette(seed);
        uint256 h = uint256(keccak256(abi.encode(seed, tokenId)));
        uint256 rungCount = 10 + (h % 8);
        uint256 wobble = h % 20;

        string memory leftRail = string.concat(
            "M ",
            (95 + wobble).toString(),
            ",335 C 115,255 175,165 228,92"
        );
        string memory rightRail = string.concat(
            "M ",
            (405 - wobble).toString(),
            ",335 C 385,255 325,165 272,92"
        );

        string memory rungs;
        for (uint256 i = 0; i < rungCount; i++) {
            uint256 t = rungCount <= 1 ? 0 : (i * 1000) / (rungCount - 1);
            uint256 y = 330 - (t * 230) / 1000;
            uint256 halfW = 150 - (t * 105) / 1000;
            uint256 cx = 250;
            if (t <= 500) {
                cx += ((500 - t) * 38) / 1000;
            } else {
                cx -= ((t - 500) * 38) / 1000;
            }
            uint256 sw = 2 + ((h >> (i * 2)) % 2);
            rungs = string.concat(
                rungs,
                '<line x1="',
                (cx - halfW).toString(),
                '" y1="',
                y.toString(),
                '" x2="',
                (cx + halfW).toString(),
                '" y2="',
                y.toString(),
                '" stroke="',
                p.purple,
                '" stroke-width="',
                sw.toString(),
                '" stroke-linecap="round" opacity="0.95"/>'
            );
        }

        string memory deco = string.concat(
            '<circle cx="250" cy="78" r="22" fill="none" stroke="',
            p.purpleDim,
            '" stroke-width="1.2"/>',
            '<ellipse cx="210" cy="95" rx="28" ry="10" fill="none" stroke="',
            p.purpleDim,
            '" stroke-width="1"/>',
            '<ellipse cx="295" cy="88" rx="22" ry="9" fill="none" stroke="',
            p.purpleDim,
            '" stroke-width="1"/>'
        );

        return string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 500 420" width="500" height="420">',
            '<defs><filter id="g"><feTurbulence type="fractalNoise" baseFrequency="0.85" numOctaves="3"/></filter></defs>',
            '<rect width="500" height="420" fill="#06080c"/>',
            '<rect width="500" height="420" filter="url(#g)" opacity="0.1"/>',
            deco,
            '<g opacity="0.35" stroke="',
            p.green,
            '" fill="none" stroke-linecap="round"><path d="',
            leftRail,
            '" stroke-width="5"/><path d="',
            rightRail,
            '" stroke-width="5"/></g>',
            '<path d="',
            leftRail,
            '" stroke="',
            p.green,
            '" stroke-width="2.2" fill="none"/>',
            '<path d="',
            rightRail,
            '" stroke="',
            p.green,
            '" stroke-width="2.2" fill="none"/>',
            rungs,
            '<text x="250" y="38" text-anchor="middle" font-family="monospace" font-size="14" fill="',
            p.green,
            '">ASCENT ',
            _pad2(tokenId),
            '</text>',
            '<text x="250" y="402" text-anchor="middle" font-family="Georgia,serif" font-size="15" font-style="italic" fill="',
            p.purple,
            '">climb higher</text>',
            "</svg>"
        );
    }

    function tokenURI(bytes32 seed, uint256 tokenId) internal pure returns (string memory) {
        string memory image = svg(seed, tokenId);
        uint256 rungCount = 10 + (uint256(seed) % 8);
        string memory json = string.concat(
            '{"name":"Ascent Ladder #',
            tokenId.toString(),
            '","description":"Neon perspective path - climb higher.","image":"data:image/svg+xml;base64,',
            Base64.encode(bytes(image)),
            '","attributes":[{"trait_type":"Rungs","value":',
            rungCount.toString(),
            '},{"trait_type":"Seed","value":"',
            _toHex32(seed),
            '"}]}'
        );
        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    function _pad2(uint256 n) internal pure returns (string memory) {
        if (n < 10) return string.concat("0", n.toString());
        return n.toString();
    }

    function _hsl(uint256 hue, uint256 sat, uint256 lum) private pure returns (string memory) {
        return string.concat("hsl(", (hue % 360).toString(), ",", sat.toString(), "%,", lum.toString(), "%)");
    }

    function _toHex32(bytes32 value) private pure returns (string memory) {
        return LibString.toHexString(uint256(value));
    }
}
