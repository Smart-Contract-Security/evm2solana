// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title SVGLib
 * @notice Pure library for constructing on-chain SVG artwork for MADE v3 tokens.
 *
 * @dev Six visual layers:
 *   1. Circle shape — outer boundary distorted by dominant category
 *   2. Rings — category-colored strokes with tier-based width
 *   3. Brightness — opacity gradient (outer=dim, inner=bright)
 *   4. Gap texture — faint radial lines between rings
 *   5. Center Core — generative shape from mint-time traits
 *   6. Ring weight — large-tier rings get subtle glow
 *
 * Category colors (hex):
 *   0 Code    = #00FF88 (green)
 *   1 Trade   = #FFAA00 (amber)
 *   2 DeFi    = #00BFFF (cyan)
 *   3 Art     = #FF6B55 (coral)
 *   4 Writing = #C4A0FF (lavender)
 *   5 DAO     = #FFFFFF (white)
 *   6 OffChain= #FFE8CC (ivory)
 */
library SVGLib {

    // ─────────────────────────────────────────────────────────────────────────
    // SVG Document Structure
    // ─────────────────────────────────────────────────────────────────────────

    function svgOpen(uint256 size) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ',
                toString(size), " ", toString(size),
                '" width="', toString(size),
                '" height="', toString(size),
                '" style="background:#000">',
                '<rect width="', toString(size),
                '" height="', toString(size),
                '" fill="#000"/>'
            )
        );
    }

    function svgClose() internal pure returns (string memory) {
        return "</svg>";
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Category Colors
    // ─────────────────────────────────────────────────────────────────────────

    function categoryColor(uint8 category) internal pure returns (string memory) {
        if (category == 0) return "#00FF88"; // Code — green
        if (category == 1) return "#FFAA00"; // Trade — amber
        if (category == 2) return "#00BFFF"; // DeFi — cyan
        if (category == 3) return "#FF6B55"; // Art — coral
        if (category == 4) return "#C4A0FF"; // Writing — lavender
        if (category == 5) return "#FFFFFF"; // DAO — white
        return "#FFE8CC";                     // OffChain — ivory
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Ring Stroke Properties
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Returns stroke-width string for a ring based on tier
    /// @dev Small=0.8, Medium=1.5, Large=2.4
    function tierStrokeWidth(uint8 tier) internal pure returns (string memory) {
        if (tier == 0) return "0.8";
        if (tier == 1) return "1.5";
        return "2.4";
    }

    /// @notice Returns stroke-dasharray for category styling
    function categoryDash(uint8 category) internal pure returns (string memory) {
        if (category == 0) return "";             // Code — solid
        if (category == 1) return "4,3";          // Trade — short dash
        if (category == 2) return "6,4";          // DeFi — long dash
        if (category == 3) return "";             // Art — solid (wobble instead)
        if (category == 4) return "1,2";          // Writing — dotted
        if (category == 5) return "";             // DAO — solid
        return "";                                 // OffChain — solid
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Colored Ring (Circle)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Renders a colored ring circle with category-specific styling
    function coloredCircle(
        uint256 cx,
        uint256 cy,
        uint256 r,
        uint8 category,
        uint8 tier,
        uint256 opacity100 // opacity * 100 (e.g. 85 = 0.85)
    ) internal pure returns (string memory) {
        string memory color = categoryColor(category);
        string memory sw = tierStrokeWidth(tier);
        string memory dash = categoryDash(category);

        string memory base = string(
            abi.encodePacked(
                '<circle cx="', toString(cx),
                '" cy="', toString(cy),
                '" r="', toString(r),
                '" fill="none" stroke="', color,
                '" stroke-width="', sw, '"'
            )
        );

        // Opacity
        string memory opStr = string(
            abi.encodePacked(
                ' stroke-opacity="0.',
                opacity100 < 10 ? string(abi.encodePacked("0", toString(opacity100))) : toString(opacity100),
                '"'
            )
        );

        // Dash array
        string memory dashAttr = bytes(dash).length > 0
            ? string(abi.encodePacked(' stroke-dasharray="', dash, '"'))
            : "";

        // Writing gets round caps
        string memory capAttr = category == 4
            ? ' stroke-linecap="round"'
            : "";

        return string(abi.encodePacked(base, opStr, dashAttr, capAttr, "/>"));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Wobbled Ring Path (for Art category)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Renders an Art ring as a wobbled path instead of perfect circle
    /// @dev Uses 48-point polygon with sine approximation for wobble
    function wobbledRing(
        uint256 cx,
        uint256 cy,
        uint256 r,
        uint8 tier,
        uint256 opacity100,
        uint256 seed
    ) internal pure returns (string memory) {
        string memory sw = tierStrokeWidth(tier);

        // Build path with 48 points
        string memory path = _wobblePath(cx, cy, r, seed, 48);

        return string(
            abi.encodePacked(
                '<path d="', path,
                '" fill="none" stroke="#FF6B55" stroke-width="', sw,
                '" stroke-opacity="0.',
                opacity100 < 10 ? string(abi.encodePacked("0", toString(opacity100))) : toString(opacity100),
                '"/>'
            )
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Core Rendering — Generative Center Shape
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Renders the Core generative shape at center
    /// @param form 0-255: organic to geometric
    /// @param palette 0-255: hue position
    /// @param complexity 0-255: element count
    /// @param luminosity 0-255: brightness
    /// @param coreSize radius of the core area
    function renderCore(
        uint256 cx,
        uint256 cy,
        uint8 form,
        uint8 palette,
        uint8 complexity,
        uint8 luminosity,
        uint256 coreSize
    ) internal pure returns (string memory) {
        string memory coreColor = _paletteToColor(palette);
        uint256 lumOpacity = 20 + uint256(luminosity) * 60 / 255; // 20-80

        // Number of elements: 2-12 based on complexity
        uint256 elements = 2 + uint256(complexity) * 10 / 255;

        string memory result = "";

        // Background glow for core
        result = string(
            abi.encodePacked(
                result,
                '<circle cx="', toString(cx),
                '" cy="', toString(cy),
                '" r="', toString(coreSize * 2),
                '" fill="', coreColor,
                '" fill-opacity="0.0', toString(lumOpacity / 10 + 1), '"/>'
            )
        );

        if (form < 85) {
            // ORGANIC — soft overlapping circles
            result = string(abi.encodePacked(result, _renderOrganicCore(cx, cy, coreSize, elements, palette, lumOpacity)));
        } else if (form < 170) {
            // MIXED — combination shapes
            result = string(abi.encodePacked(result, _renderMixedCore(cx, cy, coreSize, elements, palette, lumOpacity)));
        } else {
            // GEOMETRIC — sharp angular shapes
            result = string(abi.encodePacked(result, _renderGeometricCore(cx, cy, coreSize, elements, palette, lumOpacity)));
        }

        return result;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Gap Texture
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Renders faint radial lines between two ring radii
    /// @param dominantCat the dominant category determines pattern style
    function gapTexture(
        uint256 cx,
        uint256 cy,
        uint256 outerR,
        uint256 innerR,
        uint8 dominantCat
    ) internal pure returns (string memory) {
        if (outerR <= innerR + 6) return ""; // Too narrow for texture

        uint256 midR = (outerR + innerR) / 2;
        uint256 numLines;
        string memory result = '<g stroke-opacity="0.04">';

        if (dominantCat == 0) {
            // Code — crosshatch: 8 radial + 8 perpendicular
            numLines = 8;
            for (uint256 i = 0; i < numLines;) {
                uint256 angle100 = i * 4500 / numLines; // 0-4500 (represents 0-45 degrees * 100)
                result = string(abi.encodePacked(
                    result,
                    _radialLine(cx, cy, innerR + 2, outerR - 2, angle100),
                    _radialLine(cx, cy, innerR + 2, outerR - 2, angle100 + 2250) // +22.5 degrees
                ));
                unchecked { ++i; }
            }
        } else if (dominantCat == 1 || dominantCat == 2) {
            // Trade/DeFi — horizontal radials only
            numLines = 6;
            for (uint256 i = 0; i < numLines;) {
                uint256 angle100 = i * 6000 / numLines;
                result = string(abi.encodePacked(
                    result,
                    _radialLine(cx, cy, innerR + 2, outerR - 2, angle100)
                ));
                unchecked { ++i; }
            }
        } else {
            // Art/Writing/DAO/OffChain — sparse organic marks
            numLines = 4;
            for (uint256 i = 0; i < numLines;) {
                result = string(abi.encodePacked(
                    result,
                    '<circle cx="', toString(cx),
                    '" cy="', toString(cy),
                    '" r="', toString(midR),
                    '" fill="none" stroke="#fff" stroke-width="0.3" stroke-dasharray="1,',
                    toString(midR / 3), '"/>'
                ));
                unchecked { ++i; }
            }
        }

        result = string(abi.encodePacked(result, "</g>"));
        return result;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Glow Filter (for large-tier rings)
    // ─────────────────────────────────────────────────────────────────────────

    function glowFilter() internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                "<defs>",
                '<filter id="glow" x="-50%" y="-50%" width="200%" height="200%">',
                '<feGaussianBlur in="SourceGraphic" stdDeviation="3" result="blur"/>',
                '<feFlood flood-color="#fff" flood-opacity="0.1" result="flood"/>',
                '<feComposite in="flood" in2="blur" operator="in" result="comp"/>',
                "<feMerge>",
                '<feMergeNode in="comp"/>',
                '<feMergeNode in="SourceGraphic"/>',
                "</feMerge>",
                "</filter>",
                "</defs>"
            )
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internal Helpers
    // ─────────────────────────────────────────────────────────────────────────

    function _renderOrganicCore(
        uint256 cx, uint256 cy, uint256 size,
        uint256 elements, uint8 palette, uint256 lumOp
    ) private pure returns (string memory) {
        string memory color = _paletteToColor(palette);
        string memory result = "";

        for (uint256 i = 0; i < elements;) {
            // Position elements in a radial pattern with slight offset
            uint256 angle360 = (i * 360) / elements;
            uint256 dist = size / 3 + (i * size / elements / 4);

            // Simple x/y offset using precomputed sin/cos approximation
            (int256 dx, int256 dy) = _sinCos(angle360, dist);

            uint256 ex = uint256(int256(cx) + dx);
            uint256 ey = uint256(int256(cy) + dy);
            uint256 er = size / 4 + i * size / elements / 6;

            result = string(
                abi.encodePacked(
                    result,
                    '<circle cx="', toString(ex),
                    '" cy="', toString(ey),
                    '" r="', toString(er),
                    '" fill="', color,
                    '" fill-opacity="0.', toString(lumOp / 10 + 1), '"/>'
                )
            );
            unchecked { ++i; }
        }

        // Center dot
        result = string(
            abi.encodePacked(
                result,
                '<circle cx="', toString(cx),
                '" cy="', toString(cy),
                '" r="', toString(size / 5),
                '" fill="', color,
                '" fill-opacity="0.', toString(lumOp / 5), '"/>'
            )
        );

        return result;
    }

    function _renderGeometricCore(
        uint256 cx, uint256 cy, uint256 size,
        uint256 elements, uint8 palette, uint256 lumOp
    ) private pure returns (string memory) {
        string memory color = _paletteToColor(palette);
        // Build a polygon with 'elements' vertices
        uint256 sides = elements < 3 ? 3 : elements;
        string memory points = "";

        for (uint256 i = 0; i < sides;) {
            uint256 angle360 = (i * 360) / sides;
            (int256 dx, int256 dy) = _sinCos(angle360, size * 3 / 4);
            uint256 px = uint256(int256(cx) + dx);
            uint256 py = uint256(int256(cy) + dy);

            points = string(
                abi.encodePacked(
                    points,
                    i == 0 ? "" : " ",
                    toString(px), ",", toString(py)
                )
            );
            unchecked { ++i; }
        }

        string memory result = string(
            abi.encodePacked(
                '<polygon points="', points,
                '" fill="none" stroke="', color,
                '" stroke-width="1" stroke-opacity="0.', toString(lumOp / 5), '"/>'
            )
        );

        // Inner polygon (smaller, rotated by half-step)
        if (sides > 3) {
            points = "";
            for (uint256 i = 0; i < sides;) {
                uint256 angle360 = (i * 360) / sides + 360 / sides / 2;
                (int256 dx, int256 dy) = _sinCos(angle360, size / 2);
                uint256 px = uint256(int256(cx) + dx);
                uint256 py = uint256(int256(cy) + dy);
                points = string(
                    abi.encodePacked(points, i == 0 ? "" : " ", toString(px), ",", toString(py))
                );
                unchecked { ++i; }
            }
            result = string(
                abi.encodePacked(
                    result,
                    '<polygon points="', points,
                    '" fill="', color,
                    '" fill-opacity="0.0', toString(lumOp / 10 + 1),
                    '" stroke="', color,
                    '" stroke-width="0.5" stroke-opacity="0.', toString(lumOp / 8), '"/>'
                )
            );
        }

        // Center dot
        result = string(
            abi.encodePacked(
                result,
                '<circle cx="', toString(cx),
                '" cy="', toString(cy),
                '" r="', toString(size / 6),
                '" fill="', color,
                '" fill-opacity="0.', toString(lumOp / 4), '"/>'
            )
        );

        return result;
    }

    function _renderMixedCore(
        uint256 cx, uint256 cy, uint256 size,
        uint256 elements, uint8 palette, uint256 lumOp
    ) private pure returns (string memory) {
        string memory color = _paletteToColor(palette);
        string memory result = "";

        // Concentric rings + dots
        uint256 rings = elements / 2 + 1;
        for (uint256 i = 0; i < rings;) {
            uint256 r = size * (i + 1) / (rings + 1);
            result = string(
                abi.encodePacked(
                    result,
                    '<circle cx="', toString(cx),
                    '" cy="', toString(cy),
                    '" r="', toString(r),
                    '" fill="none" stroke="', color,
                    '" stroke-width="0.6" stroke-opacity="0.', toString(lumOp / 6), '"/>'
                )
            );
            unchecked { ++i; }
        }

        // Dots at vertices
        uint256 dots = elements;
        for (uint256 i = 0; i < dots;) {
            uint256 angle360 = (i * 360) / dots;
            (int256 dx, int256 dy) = _sinCos(angle360, size * 2 / 3);
            uint256 px = uint256(int256(cx) + dx);
            uint256 py = uint256(int256(cy) + dy);
            result = string(
                abi.encodePacked(
                    result,
                    '<circle cx="', toString(px),
                    '" cy="', toString(py),
                    '" r="2" fill="', color,
                    '" fill-opacity="0.', toString(lumOp / 5), '"/>'
                )
            );
            unchecked { ++i; }
        }

        return result;
    }

    /// @notice Map palette byte to a hex color
    /// @dev Divides 0-255 into 7 hue zones
    function _paletteToColor(uint8 palette) private pure returns (string memory) {
        if (palette < 36)  return "#FF6B35"; // warm orange
        if (palette < 73)  return "#FF4466"; // rose
        if (palette < 109) return "#FFCC00"; // gold
        if (palette < 146) return "#00FF88"; // emerald
        if (palette < 182) return "#00BFFF"; // cyan
        if (palette < 219) return "#B44AFF"; // violet
        return "#FF8855";                     // amber
    }

    /// @notice Build a wobbled closed path
    function _wobblePath(
        uint256 cx, uint256 cy, uint256 r,
        uint256 seed, uint256 points
    ) private pure returns (string memory) {
        string memory d = "";
        for (uint256 i = 0; i <= points;) {
            uint256 angle360 = (i * 360) / points;

            // Wobble: deterministic variation from seed + angle
            uint256 wobbleSeed = (seed * 127 + i * 311) % 1000;
            // ±3% radius variation
            uint256 wobble = r * wobbleSeed / 1000 / 33; // max ~3% of radius
            uint256 actualR = (wobbleSeed % 2 == 0) ? r + wobble : (r > wobble ? r - wobble : r);

            (int256 dx, int256 dy) = _sinCos(angle360, actualR);
            uint256 px = uint256(int256(cx) + dx);
            uint256 py = uint256(int256(cy) + dy);

            if (i == 0) {
                d = string(abi.encodePacked("M", toString(px), " ", toString(py)));
            } else {
                d = string(abi.encodePacked(d, "L", toString(px), " ", toString(py)));
            }
            unchecked { ++i; }
        }
        return string(abi.encodePacked(d, "Z"));
    }

    /// @notice Simple radial line from inner radius to outer radius at given angle
    function _radialLine(
        uint256 cx, uint256 cy,
        uint256 r1, uint256 r2,
        uint256 angle100 // angle * 100
    ) private pure returns (string memory) {
        uint256 angleDeg = angle100 / 100;
        (int256 dx1, int256 dy1) = _sinCos(angleDeg, r1);
        (int256 dx2, int256 dy2) = _sinCos(angleDeg, r2);

        return string(
            abi.encodePacked(
                '<line x1="', _intToString(int256(cx) + dx1),
                '" y1="', _intToString(int256(cy) + dy1),
                '" x2="', _intToString(int256(cx) + dx2),
                '" y2="', _intToString(int256(cy) + dy2),
                '" stroke="#fff" stroke-width="0.3"/>'
            )
        );
    }

    /// @notice Integer sin/cos approximation for SVG coordinate generation
    /// @dev Uses a lookup table for sin values at 15-degree intervals.
    ///      Returns (x_offset, y_offset) = (cos(angle)*radius, sin(angle)*radius)
    ///      Accuracy: ±2% which is sufficient for visual rendering
    function _sinCos(uint256 angleDeg, uint256 radius) private pure returns (int256 dx, int256 dy) {
        // Normalize angle to 0-359
        angleDeg = angleDeg % 360;

        // Sin lookup table (×1000) at 15° intervals: 0,15,30,...,90
        // sin(0)=0, sin(15)=259, sin(30)=500, sin(45)=707,
        // sin(60)=866, sin(75)=966, sin(90)=1000
        uint256[7] memory sinTable = [uint256(0), 259, 500, 707, 866, 966, 1000];

        // Get sin and cos values using symmetry
        int256 sinVal = _lookupSin(angleDeg, sinTable);
        int256 cosVal = _lookupSin((angleDeg + 90) % 360, sinTable); // cos = sin(angle + 90)

        dx = (cosVal * int256(radius)) / 1000;
        dy = (sinVal * int256(radius)) / 1000;
    }

    function _lookupSin(uint256 angleDeg, uint256[7] memory table) private pure returns (int256) {
        bool negative = false;
        uint256 a = angleDeg % 360;

        if (a >= 180) {
            negative = true;
            a -= 180;
        }
        if (a > 90) {
            a = 180 - a;
        }

        // Map to table index (0-6, for 0°-90° in 15° steps)
        uint256 idx = a / 15;
        if (idx >= 6) idx = 6;

        int256 val = int256(table[idx]);

        // Linear interpolation between table entries
        if (idx < 6) {
            uint256 remainder = a % 15;
            if (remainder > 0) {
                int256 next = int256(table[idx + 1]);
                val = val + (next - val) * int256(remainder) / 15;
            }
        }

        return negative ? -val : val;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Utility
    // ─────────────────────────────────────────────────────────────────────────

    function toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) { digits++; temp /= 10; }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + value % 10));
            value /= 10;
        }
        return string(buffer);
    }

    function _intToString(int256 value) private pure returns (string memory) {
        if (value >= 0) return toString(uint256(value));
        return string(abi.encodePacked("-", toString(uint256(-value))));
    }
}
