// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SVG} from "./SVG.sol";

/// @title Figure — woodcut hooded soul base (variant-driven, tier-agnostic)
/// @notice Returns the central figure group. Tier accents are layered on top in TierAccents.
library Figure {

    /// @notice Render the full figure group at (300, 320).
    /// @param hoodShape 0..7
    /// @param faceInside 0..7
    /// @param posture 0..3
    /// @param cloak 0..4
    function render(uint8 hoodShape, uint8 faceInside, uint8 posture, uint8 cloak)
        public
        pure
        returns (string memory)
    {
        return string(abi.encodePacked(
            '<g transform="translate(300, 320)" stroke="', SVG.INK, '" fill="none" stroke-linejoin="miter">',
            _hood(hoodShape),
            _hoodHatching(hoodShape),
            _faceVoid(hoodShape),
            _eyes(faceInside),
            _baseFolds(),
            _cloak(cloak),
            _tatteredHem(cloak),
            _arms(posture),
            '</g>'
        ));
    }

    /// @notice Universal cloak vertical fold pattern (5 lines).
    function _baseFolds() private pure returns (string memory) {
        return string(abi.encodePacked(
            '<line x1="-50" y1="0" x2="-58" y2="78" stroke-width="1.1"/>',
            '<line x1="-22" y1="-30" x2="-26" y2="78" stroke-width="1.1"/>',
            '<line x1="0" y1="-30" x2="0" y2="78" stroke-width="1.3"/>',
            '<line x1="22" y1="-30" x2="26" y2="78" stroke-width="1.1"/>',
            '<line x1="50" y1="0" x2="58" y2="78" stroke-width="1.1"/>'
        ));
    }

    /// @notice Tattered hem at the cloak bottom (omitted only when cloak=Plain).
    function _tatteredHem(uint8 cloak) private pure returns (string memory) {
        if (cloak == 0) return ""; // Plain cloak skips the hem
        return string(abi.encodePacked(
            '<path d="M -76 78 L -64 84 L -54 76 L -42 88 L -28 78 L -14 90 L 0 80 L 14 90 L 28 78 L 42 88 L 54 76 L 64 84 L 76 78" stroke-width="1.7"/>'
        ));
    }

    // ----------------------------------------------------------
    // Hood outlines
    // ----------------------------------------------------------

    function _hood(uint8 v) private pure returns (string memory) {
        if (v == 0) {
            // Plain — basic rounded hood + straight cloak
            return '<path d="M -75 -120 Q -75 -180 0 -190 Q 75 -180 75 -120 L 75 80 Q 0 90 -75 80 Z" stroke-width="2.6"/>';
        }
        if (v == 1) {
            // Peaked — taller, sharper hood crown
            return '<path d="M -72 -120 L -50 -200 L 0 -210 L 50 -200 L 72 -120 L 72 80 Q 0 90 -72 80 Z" stroke-width="2.6"/>';
        }
        if (v == 2) {
            // Pulled Back — hood drawn farther back, more face visible
            return '<path d="M -70 -100 Q -80 -170 -20 -180 Q 50 -180 80 -130 L 80 80 Q 0 90 -70 80 Z" stroke-width="2.6"/>';
        }
        if (v == 3) {
            // Arms Out — wider lower silhouette
            return '<path d="M -75 -120 Q -75 -180 0 -190 Q 75 -180 75 -120 L 100 80 Q 0 95 -100 80 Z" stroke-width="2.6"/>';
        }
        if (v == 4) {
            // Tattered — torn hem
            return string(abi.encodePacked(
                '<path d="M -75 -120 Q -75 -180 0 -190 Q 75 -180 75 -120 L 75 70 L 60 90 L 45 75 L 30 92 L 15 76 L 0 90 L -15 76 L -30 92 L -45 75 L -60 90 L -75 70 Z" stroke-width="2.6"/>'
            ));
        }
        if (v == 5) {
            // Bound — visible binding cord at waist
            return string(abi.encodePacked(
                '<path d="M -75 -120 Q -75 -180 0 -190 Q 75 -180 75 -120 L 75 80 Q 0 90 -75 80 Z" stroke-width="2.6"/>',
                '<path d="M -78 -10 L 78 -10" stroke-width="2.2"/>',
                '<path d="M -78 -4 L 78 -4" stroke-width="1.6"/>'
            ));
        }
        if (v == 6) {
            // Crowned — Legendary+ — flat crown band at top
            return string(abi.encodePacked(
                '<path d="M -75 -120 Q -75 -180 0 -190 Q 75 -180 75 -120 L 75 80 Q 0 90 -75 80 Z" stroke-width="2.8"/>',
                '<path d="M -45 -180 L -30 -200 L -15 -180 L 0 -204 L 15 -180 L 30 -200 L 45 -180" stroke-width="2.2"/>',
                '<path d="M -45 -180 L 45 -180" stroke-width="2.2"/>'
            ));
        }
        // 7 — Halo'd — Mythic only — clean pointed cone (halo comes from TierAccents)
        return string(abi.encodePacked(
            '<path d="M -75 -120 L -50 -188 L 0 -210 L 50 -188 L 75 -120 L 75 80 Q 0 90 -75 80 Z" stroke-width="2.8"/>'
        ));
    }

    function _hoodHatching(uint8 v) private pure returns (string memory) {
        // More hatching for tattered/bound, less for plain
        if (v == 0 || v == 2) {
            return string(abi.encodePacked(
                '<line x1="-50" y1="-100" x2="50" y2="-100" stroke-width="0.7"/>',
                '<line x1="-55" y1="-90"  x2="55" y2="-90" stroke-width="0.7"/>',
                '<line x1="-60" y1="-80"  x2="60" y2="-80" stroke-width="0.7"/>'
            ));
        }
        return string(abi.encodePacked(
            '<line x1="-50" y1="-100" x2="50" y2="-100" stroke-width="0.8"/>',
            '<line x1="-55" y1="-90"  x2="55" y2="-90"  stroke-width="0.8"/>',
            '<line x1="-60" y1="-80"  x2="60" y2="-80"  stroke-width="0.8"/>',
            '<line x1="-62" y1="-70"  x2="62" y2="-70"  stroke-width="0.8"/>',
            '<line x1="-62" y1="-60"  x2="62" y2="-60"  stroke-width="0.7"/>'
        ));
    }

    // ----------------------------------------------------------
    // Face void (the deep ink inside the hood)
    // ----------------------------------------------------------

    function _faceVoid(uint8 hood) private pure returns (string memory) {
        if (hood == 2) {
            // Pulled Back — wider face void
            return string(abi.encodePacked(
                '<path d="M -45 -120 Q -45 -50 0 -45 Q 45 -50 45 -120 Z" fill="', SVG.INK, '" stroke="none"/>'
            ));
        }
        return string(abi.encodePacked(
            '<path d="M -40 -120 Q -40 -55 0 -50 Q 40 -55 40 -120 Z" fill="', SVG.INK, '" stroke="none"/>'
        ));
    }

    // ----------------------------------------------------------
    // Eyes / face features inside the void
    // ----------------------------------------------------------

    function _eyes(uint8 v) private pure returns (string memory) {
        if (v == 0) {
            // Two Voids — simple pinpricks
            return string(abi.encodePacked(
                '<circle cx="-12" cy="-95" r="2.5" fill="', SVG.PARCHMENT, '" stroke="none"/>',
                '<circle cx="12" cy="-95"  r="2.5" fill="', SVG.PARCHMENT, '" stroke="none"/>'
            ));
        }
        if (v == 1) {
            // Hollow Gaze — larger hollow rings
            return string(abi.encodePacked(
                '<circle cx="-12" cy="-95" r="4" fill="none" stroke="', SVG.PARCHMENT, '" stroke-width="1.4"/>',
                '<circle cx="12" cy="-95" r="4" fill="none" stroke="', SVG.PARCHMENT, '" stroke-width="1.4"/>'
            ));
        }
        if (v == 2) {
            // Drowned — closed slits with tear lines
            return string(abi.encodePacked(
                '<line x1="-16" y1="-95" x2="-8" y2="-95" stroke="', SVG.PARCHMENT, '" stroke-width="1.6"/>',
                '<line x1="8" y1="-95" x2="16" y2="-95" stroke="', SVG.PARCHMENT, '" stroke-width="1.6"/>',
                '<line x1="-10" y1="-90" x2="-10" y2="-80" stroke="', SVG.PARCHMENT, '" stroke-width="0.9"/>',
                '<line x1="10" y1="-90" x2="10" y2="-80" stroke="', SVG.PARCHMENT, '" stroke-width="0.9"/>'
            ));
        }
        if (v == 3) {
            // Sunken — deep-set, narrow
            return string(abi.encodePacked(
                '<path d="M -16 -97 Q -12 -91 -8 -97" fill="none" stroke="', SVG.PARCHMENT, '" stroke-width="1.2"/>',
                '<path d="M 8 -97 Q 12 -91 16 -97" fill="none" stroke="', SVG.PARCHMENT, '" stroke-width="1.2"/>',
                '<circle cx="-12" cy="-94" r="1.4" fill="', SVG.PARCHMENT, '"/>',
                '<circle cx="12" cy="-94" r="1.4" fill="', SVG.PARCHMENT, '"/>'
            ));
        }
        if (v == 4) {
            // Wide — large open voids
            return string(abi.encodePacked(
                '<circle cx="-13" cy="-94" r="5" fill="', SVG.PARCHMENT, '"/>',
                '<circle cx="13" cy="-94"  r="5" fill="', SVG.PARCHMENT, '"/>',
                '<circle cx="-13" cy="-94" r="2" fill="', SVG.INK, '"/>',
                '<circle cx="13" cy="-94" r="2" fill="', SVG.INK, '"/>'
            ));
        }
        if (v == 5) {
            // Closed — peaceful slits
            return string(abi.encodePacked(
                '<path d="M -16 -94 Q -12 -91 -8 -94" fill="none" stroke="', SVG.PARCHMENT, '" stroke-width="1.3"/>',
                '<path d="M 8 -94 Q 12 -91 16 -94" fill="none" stroke="', SVG.PARCHMENT, '" stroke-width="1.3"/>'
            ));
        }
        if (v == 6) {
            // Tearmark — two voids + carved tear line below
            return string(abi.encodePacked(
                '<circle cx="-12" cy="-95" r="2.5" fill="', SVG.PARCHMENT, '"/>',
                '<circle cx="12" cy="-95"  r="2.5" fill="', SVG.PARCHMENT, '"/>',
                '<line x1="-12" y1="-90" x2="-14" y2="-76" stroke="', SVG.PARCHMENT, '" stroke-width="0.9"/>',
                '<line x1="12" y1="-90"  x2="14" y2="-76"  stroke="', SVG.PARCHMENT, '" stroke-width="0.9"/>'
            ));
        }
        // 7 — Third Eye (Mythic only) — center sigil above the eyes
        return string(abi.encodePacked(
            '<circle cx="-12" cy="-92" r="2.4" fill="', SVG.PARCHMENT, '"/>',
            '<circle cx="12" cy="-92"  r="2.4" fill="', SVG.PARCHMENT, '"/>',
            '<path d="M -8 -108 Q 0 -116 8 -108 Q 0 -100 -8 -108 Z" fill="none" stroke="', SVG.PARCHMENT, '" stroke-width="1.1"/>',
            '<circle cx="0" cy="-108" r="1.6" fill="', SVG.PARCHMENT, '"/>'
        ));
    }

    // ----------------------------------------------------------
    // Cloak fold detail
    // ----------------------------------------------------------

    function _cloak(uint8 v) private pure returns (string memory) {
        // Base folds are always drawn (see _baseFolds). This adds variant overlays.
        if (v == 0) {
            return ""; // Plain — base folds only
        }
        if (v == 1) {
            // Hatched — horizontal cross-hatching
            return string(abi.encodePacked(
                '<line x1="-44" y1="20" x2="44" y2="20" stroke-width="0.6"/>',
                '<line x1="-50" y1="40" x2="50" y2="40" stroke-width="0.6"/>',
                '<line x1="-54" y1="60" x2="54" y2="60" stroke-width="0.6"/>'
            ));
        }
        if (v == 2) {
            // Tattered — patches/tears
            return string(abi.encodePacked(
                '<path d="M -40 50 L -36 60 L -44 60 Z" fill="', SVG.INK, '"/>',
                '<path d="M 30 30 L 34 38 L 26 38 Z" fill="', SVG.INK, '"/>',
                '<path d="M -10 40 L -6 48 L -14 48 Z" fill="', SVG.INK, '"/>'
            ));
        }
        if (v == 3) {
            // Embered — Legendary+ — ember dots
            return string(abi.encodePacked(
                '<circle cx="-40" cy="20" r="1.6" fill="', SVG.EMBER, '"/>',
                '<circle cx="35" cy="40" r="1.4" fill="', SVG.EMBER, '"/>',
                '<circle cx="-10" cy="60" r="1.8" fill="', SVG.EMBER, '"/>',
                '<circle cx="20" cy="10" r="1.4" fill="', SVG.EMBER, '"/>'
            ));
        }
        // 4 — Ash Flow — Mythic — gold dots + trim
        return string(abi.encodePacked(
            '<circle cx="-30" cy="50" r="1.8" fill="', SVG.GOLD, '"/>',
            '<circle cx="0" cy="30" r="1.6" fill="', SVG.GOLD, '"/>',
            '<circle cx="30" cy="60" r="1.6" fill="', SVG.GOLD, '"/>',
            '<path d="M -45 70 L 45 70" stroke="', SVG.GOLD, '" stroke-width="0.8"/>'
        ));
    }

    // ----------------------------------------------------------
    // Arms / posture
    // ----------------------------------------------------------

    function _arms(uint8 v) private pure returns (string memory) {
        if (v == 0) {
            // Standing — arms hidden in cloak
            return "";
        }
        if (v == 1) {
            // Arms Out — both arms reaching forward
            return string(abi.encodePacked(
                '<path d="M -75 -10 Q -110 20 -130 -20" stroke-width="2.2"/>',
                '<path d="M 75 -10 Q 110 20 130 -20" stroke-width="2.2"/>',
                '<circle cx="-130" cy="-20" r="6" fill="', SVG.INK, '"/>',
                '<circle cx="130" cy="-20" r="6" fill="', SVG.INK, '"/>'
            ));
        }
        if (v == 2) {
            // Bowing — arms folded across chest
            return string(abi.encodePacked(
                '<path d="M -60 0 L -10 30" stroke-width="2.2"/>',
                '<path d="M 60 0 L 10 30" stroke-width="2.2"/>'
            ));
        }
        // 3 — Ascending — arms raised at sides
        return string(abi.encodePacked(
            '<path d="M -55 -20 Q -75 -90 -65 -150" stroke-width="2.2"/>',
            '<path d="M 55 -20 Q 75 -90 65 -150" stroke-width="2.2"/>',
            '<circle cx="-65" cy="-150" r="5" fill="', SVG.INK, '"/>',
            '<circle cx="65" cy="-150" r="5" fill="', SVG.INK, '"/>'
        ));
    }

    // ----------------------------------------------------------
    // Obol coin in position
    // ----------------------------------------------------------

    function obolInPosition(uint8 pos) public pure returns (string memory) {
        if (pos == 0) return "";
        if (pos == 1) {
            // Held Left — coin in left hand
            return string(abi.encodePacked(
                '<g transform="translate(220, 320)" stroke="', SVG.INK, '" stroke-width="1.4" fill="none">',
                '<circle cx="0" cy="0" r="10"/><circle cx="0" cy="0" r="3" fill="', SVG.INK, '"/></g>'
            ));
        }
        if (pos == 2) {
            // Held Center — coin in front of chest
            return string(abi.encodePacked(
                '<g transform="translate(300, 360)" stroke="', SVG.INK, '" stroke-width="1.4" fill="none">',
                '<circle cx="0" cy="0" r="10"/><circle cx="0" cy="0" r="3" fill="', SVG.INK, '"/></g>'
            ));
        }
        if (pos == 3) {
            // Falling — coin tumbling beside figure
            return string(abi.encodePacked(
                '<g transform="translate(380, 380) rotate(25)" stroke="', SVG.INK, '" stroke-width="1.4" fill="none">',
                '<ellipse cx="0" cy="0" rx="10" ry="3"/></g>'
            ));
        }
        // 4 — Engulfed — multiple coins sinking
        return string(abi.encodePacked(
            '<g stroke="', SVG.INK, '" stroke-width="1.2" fill="none">',
            '<circle cx="220" cy="410" r="6"/><circle cx="380" cy="420" r="5"/>',
            '<circle cx="280" cy="440" r="4"/><circle cx="350" cy="450" r="6"/>',
            '<ellipse cx="240" cy="430" rx="7" ry="2"/></g>'
        ));
    }
}
