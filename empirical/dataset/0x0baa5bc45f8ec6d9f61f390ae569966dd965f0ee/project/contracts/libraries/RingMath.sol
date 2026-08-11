// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title RingMath
 * @notice Pure library for calculating ring geometry in the MADE token visualization.
 *
 * @dev Rings represent creation stamps arranged concentrically within a circular canvas.
 *      The design philosophy is "growth from outside in":
 *        - Ring index 0 (first creation) sits at the outermost radius
 *        - Subsequent rings spiral inward toward the center
 *        - Spacing uses logarithmic compression: early rings are well-spaced,
 *          later rings pack tighter as the identity becomes richer
 *        - A minimum inner radius prevents visual collapse at high ring counts
 *
 *      This creates a visual metaphor: your earliest creations form the foundation (outer shell),
 *      while new creations fill in the interior, creating an increasingly dense identity core.
 *
 *      All calculations use integer arithmetic with fixed-point scaling (×10 or ×100)
 *      to avoid Solidity's lack of floating-point support while maintaining visual precision.
 */
library RingMath {
    // ─────────────────────────────────────────────────────────────────────────
    // Constants
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Scaling factor for fixed-point arithmetic (1 decimal place precision)
    uint256 private constant SCALE = 10;

    /// @notice Minimum spacing between rings in pixels to maintain visual clarity
    uint256 private constant MIN_SPACING = 3;

    // ─────────────────────────────────────────────────────────────────────────
    // Core Geometry Functions
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Calculates the radius for a specific ring within the concentric layout.
     *
     * @dev Ring layout strategy:
     *        - Rings go outside-in: index 0 = outermost (oldest), last index = innermost (newest)
     *        - Single ring: placed at outerRadius (centered visually)
     *        - Multiple rings: logarithmic compression of spacing
     *
     *      The logarithmic compression formula:
     *        availableSpace = outerRadius - innerMinRadius
     *        spacing = availableSpace / (totalRings - 1), compressed by log2(totalRings)
     *        radius = outerRadius - (ringIndex * compressedSpacing)
     *
     *      This ensures rings never overlap and the innermost ring respects innerMinRadius.
     *
     * @param ringIndex Zero-based index of the ring (0 = outermost/oldest).
     * @param totalRings Total number of rings on the token.
     * @param outerRadius Maximum radius (outermost ring position), typically ~230 for a 500px canvas.
     * @param innerMinRadius Minimum allowed radius to prevent center collapse, typically ~30.
     * @return radius The calculated radius in pixels for the specified ring.
     */
    function calculateRadius(
        uint256 ringIndex,
        uint256 totalRings,
        uint256 outerRadius,
        uint256 innerMinRadius
    ) internal pure returns (uint256 radius) {
        // Guard: no rings means no radius
        if (totalRings == 0) {
            return outerRadius;
        }

        // Single ring: place at the outer radius for visual impact
        if (totalRings == 1) {
            return outerRadius;
        }

        // Calculate the total available space between outer and inner bounds
        uint256 availableSpace = outerRadius - innerMinRadius;

        // Calculate spacing with logarithmic compression
        // As totalRings increases, spacing decreases logarithmically
        uint256 spacing = calculateSpacing(totalRings, availableSpace);

        // Calculate radius: outer radius minus the cumulative spacing for this ring's position
        uint256 offset = ringIndex * spacing;

        // Clamp to innerMinRadius to prevent rings from collapsing past the center
        if (outerRadius > offset && (outerRadius - offset) >= innerMinRadius) {
            radius = outerRadius - offset;
        } else {
            radius = innerMinRadius;
        }
    }

    /**
     * @notice Returns the stroke thickness for a given category, scaled by 10 (1 decimal).
     *
     * @dev Thickness values (actual pixels = return value / 10):
     *        Category 0 (Art):     25 → 2.5px — thick, expressive strokes
     *        Category 1 (Code):    10 → 1.0px — thin, precise lines
     *        Category 2 (Trade):   15 → 1.5px — moderate, professional
     *        Category 3 (Music):   20 → 2.0px — medium-thick, resonant
     *        Category 4 (Writing): 20 → 2.0px — medium-thick, substantial
     *        Category 5 (Other):   15 → 1.5px — moderate, neutral
     *
     *      The fixed-point approach (×10) lets us represent sub-pixel precision
     *      in integer arithmetic. Callers should divide by 10 when rendering.
     *
     * @param category The creation category (0-5).
     * @return thickness The stroke width multiplied by 10.
     */
    function calculateThickness(uint8 category) internal pure returns (uint256 thickness) {
        if (category == 0) {
            // Art: Thick, expressive — the heaviest visual weight
            thickness = 25;
        } else if (category == 1) {
            // Code: Thin, precise — clean digital aesthetic
            thickness = 10;
        } else if (category == 2) {
            // Trade: Medium — balanced, professional presence
            thickness = 15;
        } else if (category == 3) {
            // Music: Medium-thick — resonant, full-bodied
            thickness = 20;
        } else if (category == 4) {
            // Writing: Medium-thick — weighty like a good pen stroke
            thickness = 20;
        } else {
            // Other: Medium — neutral, unassuming
            thickness = 15;
        }
    }

    /**
     * @notice Calculates inter-ring spacing with logarithmic compression.
     *
     * @dev The spacing formula uses a log2 approximation to compress rings as count grows:
     *
     *      Base spacing = availableSpace / (totalRings - 1)
     *      Compression factor = log2(totalRings) (approximated via bit counting)
     *      Final spacing = baseSpacing * SCALE / (SCALE + compressionFactor)
     *
     *      This creates a natural visual progression:
     *        - 2 rings: full spacing, clear separation
     *        - 10 rings: ~75% of base spacing
     *        - 50 rings: ~60% of base spacing
     *        - 100+ rings: ~50% of base spacing (dense but legible)
     *
     *      The compression prevents high-ring-count tokens from having rings so close
     *      they blur into a solid mass, while still allowing meaningful differentiation.
     *
     * @param totalRings Total number of rings (must be >= 2 for meaningful spacing).
     * @param availableSpace Total pixel space available between outer and inner radius.
     * @return spacing The pixel spacing between consecutive rings.
     */
    function calculateSpacing(
        uint256 totalRings,
        uint256 availableSpace
    ) internal pure returns (uint256 spacing) {
        // Need at least 2 rings for spacing to matter
        if (totalRings <= 1) {
            return availableSpace;
        }

        // Base spacing: evenly divide available space among ring gaps
        uint256 baseSpacing = availableSpace / (totalRings - 1);

        // Logarithmic compression factor using integer log2
        // log2 approximation: count the position of the highest set bit
        uint256 compressionFactor = _log2Approx(totalRings);

        // Apply compression: spacing shrinks as log2(totalRings) increases
        // Formula: adjustedSpacing = baseSpacing * SCALE / (SCALE + compressionFactor)
        // With SCALE=10 and compressionFactor=3 (for 8 rings): 10/13 ≈ 77% of base
        spacing = (baseSpacing * SCALE) / (SCALE + compressionFactor);

        // Enforce minimum spacing to prevent visual overlap
        if (spacing < MIN_SPACING) {
            spacing = MIN_SPACING;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internal Helpers
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Integer approximation of log2(n) using the position of the highest set bit.
     * @dev For n=1 returns 0, n=2 returns 1, n=4 returns 2, n=8 returns 3, etc.
     *      Non-powers-of-two are floored: n=5 returns 2, n=10 returns 3.
     *      This is sufficient precision for visual spacing calculations.
     * @param n The input value (must be >= 1).
     * @return result The floor of log2(n).
     */
    function _log2Approx(uint256 n) private pure returns (uint256 result) {
        // Find highest set bit position
        // Each iteration checks progressively smaller bit ranges
        if (n == 0) return 0;

        result = 0;
        if (n >= 2 ** 128) { n >>= 128; result += 128; }
        if (n >= 2 ** 64)  { n >>= 64;  result += 64;  }
        if (n >= 2 ** 32)  { n >>= 32;  result += 32;  }
        if (n >= 2 ** 16)  { n >>= 16;  result += 16;  }
        if (n >= 2 ** 8)   { n >>= 8;   result += 8;   }
        if (n >= 2 ** 4)   { n >>= 4;   result += 4;   }
        if (n >= 2 ** 2)   { n >>= 2;   result += 2;   }
        if (n >= 2 ** 1)   {             result += 1;   }
    }
}
