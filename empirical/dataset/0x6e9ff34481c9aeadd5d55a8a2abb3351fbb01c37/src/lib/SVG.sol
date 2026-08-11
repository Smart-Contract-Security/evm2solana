// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @title SVG — shared building blocks for the woodcut renderer
/// @notice All renderers share the same parchment + ink palette and frame conventions.
library SVG {
    using Strings for uint256;

    // Woodcut palette (locked across all tiers)
    string internal constant INK        = "#1a0a05";
    string internal constant PARCHMENT  = "#e8e0d0";
    string internal constant ASH        = "#7a6f60";
    string internal constant EMBER      = "#b8351c"; // Legendary accent
    string internal constant GOLD       = "#b89134"; // Mythic accent

    // ----------------------------------------------------------
    // Header / footer
    // ----------------------------------------------------------

    function header() internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 600 600" preserveAspectRatio="xMidYMid meet">'
        ));
    }

    function footer() internal pure returns (string memory) {
        return "</svg>";
    }

    // ----------------------------------------------------------
    // Parchment background by tier
    // ----------------------------------------------------------

    function background(uint8 bgVariant) internal pure returns (string memory) {
        string memory fill = PARCHMENT;
        if (bgVariant == 1) fill = "#dad2c0"; // Ash Grey
        if (bgVariant == 2) fill = "#9b9388"; // Charcoal
        if (bgVariant == 3) fill = "#c8c8c0"; // River Fog
        if (bgVariant == 4) fill = "#e3b890"; // Ember Orange (Legendary+)
        if (bgVariant == 5) fill = "#ede0b8"; // Gilded Fog (Mythic)
        return string(abi.encodePacked('<rect width="600" height="600" fill="', fill, '"/>'));
    }

    // ----------------------------------------------------------
    // Parchment grain (deterministic flecks)
    // ----------------------------------------------------------

    function grain() internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<g fill="', INK, '" opacity="0.07">',
            '<circle cx="40" cy="80" r="1"/><circle cx="120" cy="40" r="1"/>',
            '<circle cx="200" cy="100" r="1"/><circle cx="320" cy="50" r="1"/>',
            '<circle cx="450" cy="90" r="1"/><circle cx="540" cy="160" r="1"/>',
            '<circle cx="80" cy="200" r="1"/><circle cx="280" cy="180" r="1"/>',
            '<circle cx="500" cy="240" r="1"/><circle cx="160" cy="300" r="1"/>',
            '<circle cx="380" cy="280" r="1"/><circle cx="60" cy="400" r="1"/>',
            '<circle cx="540" cy="380" r="1"/><circle cx="220" cy="460" r="1"/>',
            '<circle cx="430" cy="500" r="1"/><circle cx="100" cy="520" r="1"/>',
            '</g>'
        ));
    }

    // ----------------------------------------------------------
    // Frame — varies by tier (single line, double, with corner marks)
    // ----------------------------------------------------------

    function frame(uint8 tier) internal pure returns (string memory) {
        if (tier == 0) {
            // Common — single line
            return string(abi.encodePacked(
                '<rect x="40" y="40" width="520" height="520" fill="none" stroke="', INK, '" stroke-width="2"/>'
            ));
        }
        if (tier == 1) {
            // Uncommon — double line
            return string(abi.encodePacked(
                '<rect x="40" y="40" width="520" height="520" fill="none" stroke="', INK, '" stroke-width="2"/>',
                '<rect x="48" y="48" width="504" height="504" fill="none" stroke="', INK, '" stroke-width="1"/>'
            ));
        }
        if (tier == 2) {
            // Rare — double + corner marks
            return string(abi.encodePacked(
                '<rect x="40" y="40" width="520" height="520" fill="none" stroke="', INK, '" stroke-width="2.4"/>',
                '<rect x="48" y="48" width="504" height="504" fill="none" stroke="', INK, '" stroke-width="0.8"/>',
                _corners(INK, "1.6")
            ));
        }
        if (tier == 3) {
            // Epic — heavier double + corners
            return string(abi.encodePacked(
                '<rect x="36" y="36" width="528" height="528" fill="none" stroke="', INK, '" stroke-width="3"/>',
                '<rect x="48" y="48" width="504" height="504" fill="none" stroke="', INK, '" stroke-width="1"/>',
                _corners(INK, "2")
            ));
        }
        if (tier == 4) {
            // Legendary — ember accent
            return string(abi.encodePacked(
                '<rect x="36" y="36" width="528" height="528" fill="none" stroke="', INK, '" stroke-width="3"/>',
                '<rect x="48" y="48" width="504" height="504" fill="none" stroke="', EMBER, '" stroke-width="1.4"/>',
                _corners(EMBER, "2.2")
            ));
        }
        // Mythic — gold accent
        return string(abi.encodePacked(
            '<rect x="32" y="32" width="536" height="536" fill="none" stroke="', INK, '" stroke-width="3.4"/>',
            '<rect x="46" y="46" width="508" height="508" fill="none" stroke="', GOLD, '" stroke-width="1.6"/>',
            _corners(GOLD, "2.6")
        ));
    }

    function _corners(string memory color, string memory strokeWidth) private pure returns (string memory) {
        return string(abi.encodePacked(
            '<g stroke="', color, '" stroke-width="', strokeWidth, '" fill="none">',
            '<path d="M 56 56 L 76 56 M 56 56 L 56 76"/>',
            '<path d="M 544 56 L 524 56 M 544 56 L 544 76"/>',
            '<path d="M 56 544 L 76 544 M 56 544 L 56 524"/>',
            '<path d="M 544 544 L 524 544 M 544 544 L 544 524"/>',
            '</g>'
        ));
    }

    // ----------------------------------------------------------
    // Top sigil — varies by sigil trait
    // ----------------------------------------------------------

    function topSigil(uint8 sigil, uint8 tier) internal pure returns (string memory) {
        string memory color = tier == 5 ? GOLD : (tier == 4 ? EMBER : INK);
        if (sigil == 0) {
            // None — minimal mark
            return string(abi.encodePacked(
                '<g transform="translate(300, 90)" stroke="', color, '" stroke-width="1.4" fill="none">',
                '<line x1="-10" y1="0" x2="10" y2="0"/></g>'
            ));
        }
        if (sigil == 1) {
            // Crescent
            return string(abi.encodePacked(
                '<g transform="translate(300, 90)" stroke="', color, '" stroke-width="1.8" fill="none">',
                '<path d="M -20 0 Q -10 -20 10 -16 Q -4 -8 -4 4 Q -4 16 10 16 Q -10 20 -20 0 Z"/></g>'
            ));
        }
        if (sigil == 2) {
            // Cross
            return string(abi.encodePacked(
                '<g transform="translate(300, 90)" stroke="', color, '" stroke-width="2" fill="none">',
                '<line x1="0" y1="-22" x2="0" y2="22"/>',
                '<line x1="-16" y1="0" x2="16" y2="0"/></g>'
            ));
        }
        if (sigil == 3) {
            // Spiral
            return string(abi.encodePacked(
                '<g transform="translate(300, 90)" stroke="', color, '" stroke-width="1.6" fill="none">',
                '<path d="M 0 0 m -2 0 a 2 2 0 1 1 4 0 a 4 4 0 1 1 -8 0 a 6 6 0 1 1 12 0 a 8 8 0 1 1 -16 0 a 10 10 0 1 1 20 0 a 12 12 0 1 1 -24 0"/></g>'
            ));
        }
        if (sigil == 4) {
            // Eye of Passage
            return string(abi.encodePacked(
                '<g transform="translate(300, 90)" stroke="', color, '" stroke-width="1.6" fill="none">',
                '<path d="M -28 0 Q 0 -16 28 0 Q 0 16 -28 0 Z"/>',
                '<circle cx="0" cy="0" r="5"/>',
                '<circle cx="0" cy="0" r="1.6" fill="', color, '"/></g>'
            ));
        }
        // 5 = Lotus of Ash (Mythic-only)
        return string(abi.encodePacked(
            '<g transform="translate(300, 90)" stroke="', color, '" stroke-width="1.8" fill="none">',
            '<path d="M 0 16 Q -22 4 -20 -10 Q -8 -4 0 -16 Q 8 -4 20 -10 Q 22 4 0 16 Z"/>',
            '<path d="M 0 8 Q -12 0 -10 -6 Q 0 -2 0 -10 Q 0 -2 10 -6 Q 12 0 0 8 Z" stroke-width="1.1"/>',
            '<circle cx="0" cy="-2" r="2" fill="', color, '"/></g>'
        ));
    }

    // ----------------------------------------------------------
    // Signature plate — bottom token number + collection mark
    // ----------------------------------------------------------

    function signaturePlate(uint256 tokenId, uint8 tier) internal pure returns (string memory) {
        string memory color = tier == 5 ? GOLD : (tier == 4 ? EMBER : INK);
        return string(abi.encodePacked(
            '<g transform="translate(300, 548)" font-family="serif" font-size="10" fill="', color, '" text-anchor="middle">',
            '<text letter-spacing="2">No. ', tokenId.toString(), '</text></g>'
        ));
    }

    // ----------------------------------------------------------
    // River waves — universal motif below the figure
    // ----------------------------------------------------------

    function riverWaves(uint8 tier) internal pure returns (string memory) {
        string memory color = tier == 5 ? GOLD : (tier == 4 ? EMBER : INK);
        return string(abi.encodePacked(
            '<g stroke="', color, '" fill="none" stroke-width="1.2">',
            '<path d="M 70 460 Q 130 453 190 460 T 310 460 T 430 460 T 530 460"/>',
            '<path d="M 70 478 Q 130 471 190 478 T 310 478 T 430 478 T 530 478"/>',
            '<path d="M 70 496 Q 130 489 190 496 T 310 496 T 430 496 T 530 496"/>',
            '</g>'
        ));
    }

    // ----------------------------------------------------------
    // Tier mark — I / II / III / IV / V / VI bar count at bottom edge
    // ----------------------------------------------------------

    function tierMark(uint8 tier) internal pure returns (string memory) {
        string memory color = tier == 5 ? GOLD : (tier == 4 ? EMBER : INK);
        uint8 bars = tier + 1;
        // Layout: bars centered at x=300, each 4px wide, 8px apart
        int256 totalWidth = int256(uint256(bars) * 4 + (uint256(bars) - 1) * 4);
        int256 startX = int256(300) - totalWidth / 2;
        string memory marks = "";
        for (uint8 i = 0; i < bars; i++) {
            int256 x = startX + int256(uint256(i)) * 8;
            marks = string(abi.encodePacked(
                marks,
                '<rect x="', _intToStr(x), '" y="515" width="4" height="14" fill="', color, '"/>'
            ));
        }
        return marks;
    }

    function _intToStr(int256 v) private pure returns (string memory) {
        if (v < 0) return string(abi.encodePacked("-", Strings.toString(uint256(-v))));
        return Strings.toString(uint256(v));
    }

    // ----------------------------------------------------------
    // Latin designation text — appears under top sigil
    // ----------------------------------------------------------

    function latinDesignation(uint8 tier) internal pure returns (string memory) {
        string memory color = tier == 5 ? GOLD : (tier == 4 ? EMBER : INK);
        string memory word = _latin(tier);
        return string(abi.encodePacked(
            '<text x="300" y="125" font-family="serif" font-size="12" fill="', color,
            '" text-anchor="middle" letter-spacing="5">', word, '</text>'
        ));
    }

    function _latin(uint8 tier) private pure returns (string memory) {
        if (tier == 0) return "SPIRITVS";
        if (tier == 1) return "OBOLATOR";
        if (tier == 2) return "NAVTA";
        if (tier == 3) return "LANTERNARIVS";
        if (tier == 4) return "AESTVANS";
        return "FLVMINIS NATVS";
    }

    // ----------------------------------------------------------
    // Coin mark — small offset coin under the hood
    // ----------------------------------------------------------

    function coinMark(uint8 mark, uint8 tier) internal pure returns (string memory) {
        if (mark == 0) return "";
        string memory color = tier >= 4 ? (tier == 5 ? GOLD : EMBER) : INK;
        if (mark == 1) {
            return string(abi.encodePacked(
                '<g transform="translate(300, 460)" stroke="', color, '" stroke-width="1.4" fill="none">',
                '<circle cx="0" cy="0" r="14"/><line x1="-6" y1="0" x2="6" y2="0"/></g>'
            ));
        }
        if (mark == 2) {
            return string(abi.encodePacked(
                '<g transform="translate(300, 460)" stroke="', color, '" stroke-width="1.4" fill="none">',
                '<circle cx="0" cy="0" r="14"/>',
                '<line x1="-6" y1="-3" x2="6" y2="-3"/><line x1="-6" y1="3" x2="6" y2="3"/></g>'
            ));
        }
        if (mark == 3) {
            return string(abi.encodePacked(
                '<g transform="translate(300, 460)" stroke="', color, '" stroke-width="1.4" fill="none">',
                '<circle cx="0" cy="0" r="14"/>',
                '<path d="M 0 -8 L 7 6 L -7 6 Z"/></g>'
            ));
        }
        if (mark == 4) {
            return string(abi.encodePacked(
                '<g transform="translate(300, 460)" stroke="', color, '" stroke-width="1.4" fill="none">',
                '<circle cx="0" cy="0" r="14"/>',
                '<line x1="-6" y1="-4" x2="6" y2="-4"/><line x1="-6" y1="0" x2="6" y2="0"/>',
                '<line x1="-6" y1="4" x2="6" y2="4"/></g>'
            ));
        }
        // 5 — Burning Brand (Legendary+)
        return string(abi.encodePacked(
            '<g transform="translate(300, 460)" stroke="', color, '" stroke-width="1.8" fill="none">',
            '<circle cx="0" cy="0" r="14" stroke-width="2.2"/>',
            '<path d="M 0 -6 Q -3 -2 0 0 Q 3 -2 0 -6 M 0 0 Q -4 4 0 8 Q 4 4 0 0"/></g>'
        ));
    }
}
