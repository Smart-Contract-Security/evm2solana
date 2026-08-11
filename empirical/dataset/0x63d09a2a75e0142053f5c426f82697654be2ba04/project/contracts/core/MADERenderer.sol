// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {MADECore} from "./MADECore.sol";
import {SVGLib} from "../libraries/SVGLib.sol";
import {RingMath} from "../libraries/RingMath.sol";

/**
 * @title MADERenderer
 * @notice Stateless renderer for MADE v3 — six visual layers.
 *
 * @dev Generates colored ring visualizations with generative Core shapes.
 *
 *      Canvas: 500×500. Black background. Colored rings.
 *
 *      Layer 1: Circle shape (boundary, always present)
 *      Layer 2: Rings with category colors + tier stroke widths
 *      Layer 3: Brightness gradient (outer=dim, inner=bright)
 *      Layer 4: Gap texture between rings (faint, based on dominant category)
 *      Layer 5: Center Core (generative shape from mint traits)
 *      Layer 6: Large-tier ring glow effect
 */
contract MADERenderer {
    using Strings for uint256;
    using Strings for address;

    uint256 private constant CANVAS_SIZE = 500;
    uint256 private constant CENTER = 250;
    uint256 private constant OUTER_RADIUS = 230;
    uint256 private constant INNER_MIN_RADIUS = 30;

    string[7] private CATEGORY_NAMES = [
        "Code", "Trade", "DeFi", "Art", "Writing", "DAO", "OffChain"
    ];

    // ─────────────────────────────────────────────────────────────────────────
    // SVG Rendering — All 6 Layers
    // ─────────────────────────────────────────────────────────────────────────

    function render(
        uint256 tokenId,
        address owner,
        bytes32 seed,
        MADECore.RingData[] memory rings,
        MADECore.CoreTraits memory core,
        uint256 _ringCount
    ) external pure returns (string memory svg) {
        tokenId; owner; // Reserved for future use

        svg = SVGLib.svgOpen(CANVAS_SIZE);

        // Layer 6: Add glow filter if any large-tier rings exist
        bool hasLargeTier = false;
        for (uint256 i = 0; i < _ringCount;) {
            if (rings[i].tier == 2) { hasLargeTier = true; break; }
            unchecked { ++i; }
        }
        if (hasLargeTier) {
            svg = string(abi.encodePacked(svg, SVGLib.glowFilter()));
        }

        // Layer 1: Outer boundary circle
        svg = string(
            abi.encodePacked(
                svg,
                '<circle cx="', SVGLib.toString(CENTER),
                '" cy="', SVGLib.toString(CENTER),
                '" r="', SVGLib.toString(OUTER_RADIUS),
                '" fill="none" stroke="#fff" stroke-width="0.5" stroke-opacity="0.12"/>'
            )
        );

        // Layer 5: Center Core (always rendered, even with 0 rings)
        uint256 coreSize = 35 + (_ringCount * 3); // Starts much larger (HD), grows with rings
        if (coreSize > 85) coreSize = 85; // Cap at ~35% of total width (radius 85 = diameter 170)
        svg = string(
            abi.encodePacked(
                svg,
                SVGLib.renderCore(
                    CENTER, CENTER,
                    core.form, core.palette, core.complexity, core.luminosity,
                    coreSize
                )
            )
        );

        // Layers 2-4: Rings + brightness + gap texture
        uint8 dominantCat = _getDominantCategory(rings, _ringCount);

        for (uint256 i = 0; i < _ringCount;) {
            uint256 radius = RingMath.calculateRadius(
                i, _ringCount, OUTER_RADIUS, INNER_MIN_RADIUS
            );

            // Layer 3: Brightness gradient
            // Outer ring (i=0) = 55% opacity, inner ring (last) = 95%
            uint256 opacity100;
            if (_ringCount == 1) {
                opacity100 = 90;
            } else {
                opacity100 = 55 + (i * 40) / (_ringCount - 1);
            }

            // Layer 2: Colored ring
            if (rings[i].category == 3) {
                // Art rings get wobbled path
                uint256 ringSeed = uint256(keccak256(abi.encodePacked(seed, i)));
                svg = string(
                    abi.encodePacked(
                        svg,
                        SVGLib.wobbledRing(
                            CENTER, CENTER, radius,
                            rings[i].tier, opacity100,
                            ringSeed
                        )
                    )
                );
            } else {
                svg = string(
                    abi.encodePacked(
                        svg,
                        SVGLib.coloredCircle(
                            CENTER, CENTER, radius,
                            rings[i].category, rings[i].tier,
                            opacity100
                        )
                    )
                );
            }

            // Layer 6: Large-tier glow
            if (rings[i].tier == 2) {
                svg = string(
                    abi.encodePacked(
                        svg,
                        '<circle cx="', SVGLib.toString(CENTER),
                        '" cy="', SVGLib.toString(CENTER),
                        '" r="', SVGLib.toString(radius),
                        '" fill="none" stroke="', SVGLib.categoryColor(rings[i].category),
                        '" stroke-width="1" stroke-opacity="0.12" filter="url(#glow)"/>'
                    )
                );
            }

            // Layer 4: Gap texture between consecutive rings
            if (i > 0 && i % 3 == 0) {
                uint256 prevRadius = RingMath.calculateRadius(
                    i - 1, _ringCount, OUTER_RADIUS, INNER_MIN_RADIUS
                );
                if (prevRadius > radius + 8) {
                    svg = string(
                        abi.encodePacked(
                            svg,
                            SVGLib.gapTexture(CENTER, CENTER, prevRadius, radius, dominantCat)
                        )
                    );
                }
            }

            unchecked { ++i; }
        }

        svg = string(abi.encodePacked(svg, SVGLib.svgClose()));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // JSON Metadata
    // ─────────────────────────────────────────────────────────────────────────

    function tokenURI(
        uint256 tokenId,
        string memory name,
        address owner,
        bytes32 seed,
        MADECore.RingData[] memory rings,
        MADECore.CoreTraits memory core,
        uint256 _ringCount
    ) external view returns (string memory) {
        string memory svgImage = this.render(tokenId, owner, seed, rings, core, _ringCount);

        string memory imageURI = string(
            abi.encodePacked(
                "data:image/svg+xml;base64,",
                Base64.encode(bytes(svgImage))
            )
        );

        string memory attributes = _buildAttributes(_ringCount, core, rings);

        string memory json = string(
            abi.encodePacked(
                '{"name":"', name,
                '","description":"MADE: Living on-chain generative art that evolves from real activity. Each ring represents a verified action. The Core is your unique generative seed.',
                '","image":"', imageURI,
                '","attributes":', attributes, "}"
            )
        );

        return string(
            abi.encodePacked(
                "data:application/json;base64,",
                Base64.encode(bytes(json))
            )
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internal
    // ─────────────────────────────────────────────────────────────────────────

    function _buildAttributes(
        uint256 _ringCount,
        MADECore.CoreTraits memory core,
        MADECore.RingData[] memory rings
    ) internal view returns (string memory) {
        // Core form name
        string memory formName;
        if (core.form < 85) formName = "Organic";
        else if (core.form < 170) formName = "Hybrid";
        else formName = "Geometric";

        // Luminosity name
        string memory lumName;
        if (core.luminosity < 64) lumName = "Dim";
        else if (core.luminosity < 128) lumName = "Steady";
        else if (core.luminosity < 192) lumName = "Bright";
        else lumName = "Radiant";

        // Complexity name
        string memory compName;
        uint256 elements = 2 + uint256(core.complexity) * 10 / 255;
        if (elements <= 3) compName = "Minimal";
        else if (elements <= 6) compName = "Moderate";
        else if (elements <= 9) compName = "Complex";
        else compName = "Intricate";

        string memory attrs = string(
            abi.encodePacked(
                '[{"trait_type":"Ring Count","value":', SVGLib.toString(_ringCount),
                '},{"trait_type":"Core Form","value":"', formName,
                '"},{"trait_type":"Core Luminosity","value":"', lumName,
                '"},{"trait_type":"Core Complexity","value":"', compName, '"}'
            )
        );

        // Category counts
        uint256[7] memory catCounts;
        uint256[3] memory tierCounts;
        for (uint256 i = 0; i < rings.length;) {
            if (rings[i].category < 7) catCounts[rings[i].category]++;
            if (rings[i].tier < 3) tierCounts[rings[i].tier]++;
            unchecked { ++i; }
        }

        for (uint256 i = 0; i < 7;) {
            if (catCounts[i] > 0) {
                attrs = string(
                    abi.encodePacked(
                        attrs,
                        ',{"trait_type":"', CATEGORY_NAMES[i],
                        ' Rings","value":', SVGLib.toString(catCounts[i]), "}"
                    )
                );
            }
            unchecked { ++i; }
        }

        // Tier counts as traits
        if (tierCounts[2] > 0) {
            attrs = string(
                abi.encodePacked(
                    attrs,
                    ',{"trait_type":"Bold Rings","value":', SVGLib.toString(tierCounts[2]), "}"
                )
            );
        }

        return string(abi.encodePacked(attrs, "]"));
    }

    function _getDominantCategory(
        MADECore.RingData[] memory rings,
        uint256 count
    ) internal pure returns (uint8) {
        if (count == 0) return 0;

        uint256[7] memory counts;
        for (uint256 i = 0; i < count;) {
            if (rings[i].category < 7) counts[rings[i].category]++;
            unchecked { ++i; }
        }

        uint8 dominant = 0;
        uint256 maxCount = 0;
        for (uint8 i = 0; i < 7;) {
            if (counts[i] > maxCount) {
                maxCount = counts[i];
                dominant = i;
            }
            unchecked { ++i; }
        }

        return dominant;
    }
}
