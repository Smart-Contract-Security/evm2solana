// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title SpriteDataSpecies
 * @notice Stores the 6 species sprites + body variant color swap tables.
 *         Renderer calls speciesSVG(idx) for base sprite, then applies variant
 *         swap colors via _replaceColor() in the Renderer.
 *
 *  Variant strategy: each variant is just a list of color substitutions
 *  applied to the base sprite. Saves ~50 KB vs storing each variant
 *  as a full sprite.
 */
contract SpriteDataSpecies {

    // ============ SPECIES BASE SPRITES ============

    function speciesSVG(uint8 idx) external pure returns (string memory) {
        if (idx == 0) return _dogSVG();
        if (idx == 1) return _catSVG();
        if (idx == 2) return _frogSVG();
        if (idx == 3) return _bearSVG();
        if (idx == 4) return _penguinSVG();
        return _apeSVG();
    }

    function _dogSVG() private pure returns (string memory) {
        return string(abi.encodePacked(
            '<rect x="5" y="3" width="2" height="1" fill="#A87D4A"/>',
            '<rect x="17" y="3" width="2" height="1" fill="#A87D4A"/>',
            '<rect x="4" y="4" width="4" height="1" fill="#A87D4A"/>',
            '<rect x="16" y="4" width="4" height="1" fill="#A87D4A"/>',
            '<rect x="5" y="4" width="2" height="1" fill="#F4D9A8"/>',
            '<rect x="17" y="4" width="2" height="1" fill="#F4D9A8"/>',
            '<rect x="5" y="5" width="14" height="1" fill="#D4A574"/>',
            '<rect x="4" y="6" width="16" height="1" fill="#D4A574"/>',
            '<rect x="3" y="7" width="18" height="1" fill="#D4A574"/>',
            '<rect x="3" y="8" width="18" height="1" fill="#D4A574"/>',
            '<rect x="6" y="8" width="2" height="1" fill="#fff"/>',
            '<rect x="16" y="8" width="2" height="1" fill="#fff"/>',
            '<rect x="7" y="8" width="1" height="1" fill="#1A0A0A"/>',
            '<rect x="17" y="8" width="1" height="1" fill="#1A0A0A"/>',
            '<rect x="3" y="9" width="18" height="1" fill="#D4A574"/>',
            '<rect x="5" y="9" width="1" height="1" fill="#FFAFC2"/>',
            '<rect x="18" y="9" width="1" height="1" fill="#FFAFC2"/>',
            '<rect x="8" y="9" width="8" height="1" fill="#F4D9A8"/>',
            '<rect x="11" y="9" width="2" height="1" fill="#1A0A0A"/>',
            '<rect x="4" y="10" width="16" height="1" fill="#D4A574"/>',
            '<rect x="7" y="10" width="10" height="1" fill="#F4D9A8"/>',
            '<rect x="10" y="10" width="4" height="1" fill="#3D2817"/>',
            '<rect x="5" y="11" width="14" height="1" fill="#D4A574"/>',
            '<rect x="8" y="11" width="8" height="1" fill="#F4D9A8"/>',
            '<rect x="7" y="12" width="10" height="1" fill="#D4A574"/>',
            '<rect x="6" y="13" width="12" height="1" fill="#D4A574"/>',
            '<rect x="5" y="14" width="14" height="1" fill="#D4A574"/>',
            '<rect x="9" y="14" width="6" height="1" fill="#F4D9A8"/>',
            '<rect x="4" y="15" width="16" height="1" fill="#D4A574"/>',
            '<rect x="8" y="15" width="8" height="1" fill="#F4D9A8"/>',
            '<rect x="4" y="16" width="16" height="1" fill="#D4A574"/>',
            '<rect x="8" y="16" width="8" height="1" fill="#F4D9A8"/>',
            '<rect x="4" y="17" width="16" height="1" fill="#D4A574"/>',
            '<rect x="7" y="17" width="10" height="1" fill="#F4D9A8"/>',
            '<rect x="4" y="18" width="16" height="1" fill="#D4A574"/>',
            '<rect x="5" y="19" width="14" height="1" fill="#D4A574"/>',
            '<rect x="6" y="20" width="4" height="2" fill="#A87D4A"/>',
            '<rect x="14" y="20" width="4" height="2" fill="#A87D4A"/>'
        ));
    }

    function _catSVG() private pure returns (string memory) {
        return string(abi.encodePacked(
            '<rect x="5" y="2" width="1" height="1" fill="#E8843D"/>',
            '<rect x="18" y="2" width="1" height="1" fill="#E8843D"/>',
            '<rect x="5" y="3" width="2" height="1" fill="#E8843D"/>',
            '<rect x="17" y="3" width="2" height="1" fill="#E8843D"/>',
            '<rect x="4" y="4" width="4" height="1" fill="#E8843D"/>',
            '<rect x="16" y="4" width="4" height="1" fill="#E8843D"/>',
            '<rect x="5" y="4" width="2" height="1" fill="#FFB084"/>',
            '<rect x="17" y="4" width="2" height="1" fill="#FFB084"/>',
            '<rect x="4" y="5" width="16" height="1" fill="#E8843D"/>',
            '<rect x="3" y="6" width="18" height="1" fill="#E8843D"/>',
            '<rect x="3" y="7" width="18" height="1" fill="#E8843D"/>',
            '<rect x="6" y="7" width="3" height="1" fill="#5BAA3D"/>',
            '<rect x="15" y="7" width="3" height="1" fill="#5BAA3D"/>',
            '<rect x="3" y="8" width="18" height="1" fill="#E8843D"/>',
            '<rect x="6" y="8" width="3" height="1" fill="#5BAA3D"/>',
            '<rect x="15" y="8" width="3" height="1" fill="#5BAA3D"/>',
            '<rect x="7" y="8" width="1" height="1" fill="#1A0A0A"/>',
            '<rect x="16" y="8" width="1" height="1" fill="#1A0A0A"/>',
            '<rect x="3" y="9" width="18" height="1" fill="#E8843D"/>',
            '<rect x="9" y="9" width="6" height="1" fill="#FFE8D1"/>',
            '<rect x="11" y="9" width="2" height="1" fill="#FF8FA3"/>',
            '<rect x="4" y="10" width="16" height="1" fill="#E8843D"/>',
            '<rect x="7" y="10" width="10" height="1" fill="#FFE8D1"/>',
            '<rect x="10" y="10" width="4" height="1" fill="#3D2817"/>',
            '<rect x="5" y="11" width="14" height="1" fill="#E8843D"/>',
            '<rect x="8" y="11" width="8" height="1" fill="#FFE8D1"/>',
            '<rect x="6" y="12" width="12" height="1" fill="#E8843D"/>',
            '<rect x="5" y="13" width="14" height="1" fill="#E8843D"/>',
            '<rect x="4" y="14" width="16" height="1" fill="#E8843D"/>',
            '<rect x="9" y="14" width="6" height="1" fill="#FFE8D1"/>',
            '<rect x="4" y="15" width="16" height="1" fill="#E8843D"/>',
            '<rect x="8" y="15" width="8" height="1" fill="#FFE8D1"/>',
            '<rect x="4" y="16" width="16" height="1" fill="#E8843D"/>',
            '<rect x="8" y="16" width="8" height="1" fill="#FFE8D1"/>',
            '<rect x="4" y="17" width="16" height="1" fill="#E8843D"/>',
            '<rect x="7" y="17" width="10" height="1" fill="#FFE8D1"/>',
            '<rect x="5" y="18" width="14" height="1" fill="#E8843D"/>',
            '<rect x="6" y="19" width="12" height="1" fill="#E8843D"/>',
            '<rect x="6" y="20" width="4" height="2" fill="#E8843D"/>',
            '<rect x="14" y="20" width="4" height="2" fill="#E8843D"/>'
        ));
    }

    function _frogSVG() private pure returns (string memory) {
        // Body drawn first; head overlays on top so eyes show above body green at y=7-8
        return string(abi.encodePacked(
            '<rect x="3" y="7" width="18" height="1" fill="#5BB041"/>',
            '<rect x="2" y="8" width="20" height="1" fill="#5BB041"/>',
            '<rect x="11" y="8" width="2" height="1" fill="#1F4A1A"/>',
            '<rect x="2" y="9" width="20" height="1" fill="#5BB041"/>',
            '<rect x="2" y="10" width="20" height="1" fill="#5BB041"/>',
            '<rect x="6" y="10" width="12" height="1" fill="#1F4A1A"/>',
            '<rect x="2" y="11" width="20" height="1" fill="#5BB041"/>',
            '<rect x="2" y="12" width="20" height="1" fill="#5BB041"/>',
            '<rect x="6" y="12" width="12" height="1" fill="#A4D693"/>',
            '<rect x="2" y="13" width="20" height="1" fill="#5BB041"/>',
            '<rect x="5" y="13" width="14" height="1" fill="#A4D693"/>',
            '<rect x="3" y="14" width="18" height="1" fill="#5BB041"/>',
            '<rect x="5" y="14" width="14" height="1" fill="#A4D693"/>',
            '<rect x="3" y="15" width="18" height="1" fill="#5BB041"/>',
            '<rect x="5" y="15" width="14" height="1" fill="#A4D693"/>',
            '<rect x="4" y="16" width="16" height="1" fill="#5BB041"/>',
            '<rect x="6" y="16" width="12" height="1" fill="#A4D693"/>',
            '<rect x="5" y="17" width="14" height="1" fill="#5BB041"/>',
            '<rect x="6" y="18" width="12" height="1" fill="#5BB041"/>',
            '<rect x="6" y="19" width="3" height="1" fill="#5BB041"/>',
            '<rect x="15" y="19" width="3" height="1" fill="#5BB041"/>',
            '<rect x="6" y="20" width="3" height="2" fill="#5BB041"/>',
            '<rect x="15" y="20" width="3" height="2" fill="#5BB041"/>',
            // Head overlay (shifted down 2 rows so hats fit naturally above)
            '<rect x="5" y="5" width="3" height="1" fill="#5BB041"/>',
            '<rect x="16" y="5" width="3" height="1" fill="#5BB041"/>',
            '<rect x="8" y="5" width="8" height="1" fill="#5BB041"/>',
            '<rect x="4" y="6" width="5" height="1" fill="#5BB041"/>',
            '<rect x="15" y="6" width="5" height="1" fill="#5BB041"/>',
            '<rect x="5" y="6" width="3" height="1" fill="#fff"/>',
            '<rect x="16" y="6" width="3" height="1" fill="#fff"/>',
            '<rect x="9" y="6" width="6" height="1" fill="#5BB041"/>',
            '<rect x="4" y="7" width="5" height="1" fill="#5BB041"/>',
            '<rect x="15" y="7" width="5" height="1" fill="#5BB041"/>',
            '<rect x="5" y="7" width="3" height="1" fill="#fff"/>',
            '<rect x="15" y="7" width="3" height="1" fill="#fff"/>',
            '<rect x="6" y="7" width="1" height="1" fill="#1A0A0A"/>',
            '<rect x="16" y="7" width="1" height="1" fill="#1A0A0A"/>',
            '<rect x="9" y="7" width="6" height="1" fill="#5BB041"/>',
            '<rect x="4" y="8" width="5" height="1" fill="#5BB041"/>',
            '<rect x="15" y="8" width="5" height="1" fill="#5BB041"/>'
        ));
    }

    function _bearSVG() private pure returns (string memory) {
        return string(abi.encodePacked(
            '<rect x="5" y="3" width="2" height="1" fill="#7C4A1F"/>',
            '<rect x="17" y="3" width="2" height="1" fill="#7C4A1F"/>',
            '<rect x="4" y="4" width="4" height="1" fill="#7C4A1F"/>',
            '<rect x="16" y="4" width="4" height="1" fill="#7C4A1F"/>',
            '<rect x="5" y="4" width="2" height="1" fill="#3D2817"/>',
            '<rect x="17" y="4" width="2" height="1" fill="#3D2817"/>',
            '<rect x="5" y="5" width="14" height="1" fill="#7C4A1F"/>',
            '<rect x="4" y="6" width="16" height="1" fill="#7C4A1F"/>',
            '<rect x="3" y="7" width="18" height="1" fill="#7C4A1F"/>',
            '<rect x="3" y="8" width="18" height="1" fill="#7C4A1F"/>',
            '<rect x="6" y="8" width="2" height="1" fill="#fff"/>',
            '<rect x="16" y="8" width="2" height="1" fill="#fff"/>',
            '<rect x="7" y="8" width="1" height="1" fill="#1A0A0A"/>',
            '<rect x="17" y="8" width="1" height="1" fill="#1A0A0A"/>',
            '<rect x="3" y="9" width="18" height="1" fill="#7C4A1F"/>',
            '<rect x="9" y="9" width="6" height="1" fill="#E8C9A0"/>',
            '<rect x="11" y="9" width="2" height="1" fill="#1A0A0A"/>',
            '<rect x="4" y="10" width="16" height="1" fill="#7C4A1F"/>',
            '<rect x="8" y="10" width="8" height="1" fill="#E8C9A0"/>',
            '<rect x="10" y="10" width="4" height="1" fill="#3D2817"/>',
            '<rect x="5" y="11" width="14" height="1" fill="#7C4A1F"/>',
            '<rect x="8" y="11" width="8" height="1" fill="#E8C9A0"/>',
            '<rect x="6" y="12" width="12" height="1" fill="#7C4A1F"/>',
            '<rect x="5" y="13" width="14" height="1" fill="#7C4A1F"/>',
            '<rect x="4" y="14" width="16" height="1" fill="#7C4A1F"/>',
            '<rect x="9" y="14" width="6" height="1" fill="#E8C9A0"/>',
            '<rect x="4" y="15" width="16" height="1" fill="#7C4A1F"/>',
            '<rect x="8" y="15" width="8" height="1" fill="#E8C9A0"/>',
            '<rect x="4" y="16" width="16" height="1" fill="#7C4A1F"/>',
            '<rect x="8" y="16" width="8" height="1" fill="#E8C9A0"/>',
            '<rect x="4" y="17" width="16" height="1" fill="#7C4A1F"/>',
            '<rect x="7" y="17" width="10" height="1" fill="#E8C9A0"/>',
            '<rect x="4" y="18" width="16" height="1" fill="#7C4A1F"/>',
            '<rect x="5" y="19" width="14" height="1" fill="#7C4A1F"/>',
            '<rect x="6" y="20" width="4" height="2" fill="#A86B2D"/>',
            '<rect x="14" y="20" width="4" height="2" fill="#A86B2D"/>'
        ));
    }

    function _penguinSVG() private pure returns (string memory) {
        return string(abi.encodePacked(
            '<rect x="11" y="2" width="2" height="1" fill="#6BA6E8"/>',
            '<rect x="9" y="3" width="6" height="1" fill="#6BA6E8"/>',
            '<rect x="7" y="4" width="10" height="1" fill="#6BA6E8"/>',
            '<rect x="6" y="5" width="12" height="1" fill="#6BA6E8"/>',
            '<rect x="5" y="6" width="14" height="1" fill="#6BA6E8"/>',
            '<rect x="5" y="7" width="14" height="1" fill="#6BA6E8"/>',
            '<rect x="7" y="7" width="3" height="1" fill="#fff"/>',
            '<rect x="14" y="7" width="3" height="1" fill="#fff"/>',
            '<rect x="8" y="7" width="2" height="1" fill="#1A0A0A"/>',
            '<rect x="14" y="7" width="2" height="1" fill="#1A0A0A"/>',
            '<rect x="5" y="8" width="14" height="1" fill="#6BA6E8"/>',
            '<rect x="7" y="8" width="3" height="1" fill="#fff"/>',
            '<rect x="14" y="8" width="3" height="1" fill="#fff"/>',
            '<rect x="6" y="8" width="1" height="1" fill="#FF8FA3"/>',
            '<rect x="17" y="8" width="1" height="1" fill="#FF8FA3"/>',
            '<rect x="5" y="9" width="14" height="1" fill="#6BA6E8"/>',
            '<rect x="10" y="9" width="4" height="1" fill="#FFA94D"/>',
            '<rect x="4" y="10" width="16" height="1" fill="#6BA6E8"/>',
            '<rect x="8" y="10" width="8" height="1" fill="#FAF5E6"/>',
            '<rect x="11" y="10" width="2" height="1" fill="#FFA94D"/>',
            '<rect x="3" y="11" width="2" height="1" fill="#6BA6E8"/>',
            '<rect x="19" y="11" width="2" height="1" fill="#6BA6E8"/>',
            '<rect x="5" y="11" width="14" height="1" fill="#6BA6E8"/>',
            '<rect x="7" y="11" width="10" height="1" fill="#FAF5E6"/>',
            '<rect x="2" y="12" width="3" height="1" fill="#6BA6E8"/>',
            '<rect x="19" y="12" width="3" height="1" fill="#6BA6E8"/>',
            '<rect x="5" y="12" width="14" height="1" fill="#6BA6E8"/>',
            '<rect x="7" y="12" width="10" height="1" fill="#FAF5E6"/>',
            '<rect x="2" y="13" width="3" height="1" fill="#6BA6E8"/>',
            '<rect x="19" y="13" width="3" height="1" fill="#6BA6E8"/>',
            '<rect x="5" y="13" width="14" height="1" fill="#6BA6E8"/>',
            '<rect x="7" y="13" width="10" height="1" fill="#FAF5E6"/>',
            '<rect x="2" y="14" width="3" height="1" fill="#6BA6E8"/>',
            '<rect x="19" y="14" width="3" height="1" fill="#6BA6E8"/>',
            '<rect x="5" y="14" width="14" height="1" fill="#6BA6E8"/>',
            '<rect x="7" y="14" width="10" height="1" fill="#FAF5E6"/>',
            '<rect x="3" y="15" width="2" height="1" fill="#6BA6E8"/>',
            '<rect x="19" y="15" width="2" height="1" fill="#6BA6E8"/>',
            '<rect x="5" y="15" width="14" height="1" fill="#6BA6E8"/>',
            '<rect x="7" y="15" width="10" height="1" fill="#FAF5E6"/>',
            '<rect x="5" y="16" width="14" height="1" fill="#6BA6E8"/>',
            '<rect x="7" y="16" width="10" height="1" fill="#FAF5E6"/>',
            '<rect x="5" y="17" width="14" height="1" fill="#6BA6E8"/>',
            '<rect x="7" y="17" width="10" height="1" fill="#FAF5E6"/>',
            '<rect x="5" y="18" width="14" height="1" fill="#6BA6E8"/>',
            '<rect x="7" y="18" width="10" height="1" fill="#FAF5E6"/>',
            '<rect x="5" y="19" width="14" height="1" fill="#6BA6E8"/>',
            '<rect x="7" y="19" width="10" height="1" fill="#FAF5E6"/>',
            '<rect x="6" y="20" width="12" height="1" fill="#6BA6E8"/>',
            '<rect x="8" y="20" width="8" height="1" fill="#FAF5E6"/>',
            '<rect x="6" y="21" width="4" height="1" fill="#FFA94D"/>',
            '<rect x="14" y="21" width="4" height="1" fill="#FFA94D"/>'
        ));
    }

    function _apeSVG() private pure returns (string memory) {
        return string(abi.encodePacked(
            '<rect x="6" y="3" width="12" height="1" fill="#7A5236"/>',
            '<rect x="5" y="4" width="14" height="1" fill="#7A5236"/>',
            '<rect x="4" y="5" width="16" height="1" fill="#7A5236"/>',
            '<rect x="3" y="6" width="18" height="1" fill="#7A5236"/>',
            '<rect x="3" y="7" width="18" height="1" fill="#7A5236"/>',
            '<rect x="6" y="7" width="12" height="1" fill="#D4A574"/>',
            '<rect x="2" y="8" width="2" height="1" fill="#7A5236"/>',
            '<rect x="20" y="8" width="2" height="1" fill="#7A5236"/>',
            '<rect x="3" y="8" width="18" height="1" fill="#7A5236"/>',
            '<rect x="5" y="8" width="14" height="1" fill="#D4A574"/>',
            '<rect x="2" y="9" width="2" height="1" fill="#7A5236"/>',
            '<rect x="20" y="9" width="2" height="1" fill="#7A5236"/>',
            '<rect x="3" y="9" width="18" height="1" fill="#7A5236"/>',
            '<rect x="5" y="9" width="14" height="1" fill="#D4A574"/>',
            '<rect x="7" y="9" width="2" height="1" fill="#fff"/>',
            '<rect x="15" y="9" width="2" height="1" fill="#fff"/>',
            '<rect x="8" y="9" width="1" height="1" fill="#1A0A0A"/>',
            '<rect x="15" y="9" width="1" height="1" fill="#1A0A0A"/>',
            '<rect x="2" y="10" width="2" height="1" fill="#7A5236"/>',
            '<rect x="20" y="10" width="2" height="1" fill="#7A5236"/>',
            '<rect x="3" y="10" width="18" height="1" fill="#7A5236"/>',
            '<rect x="5" y="10" width="14" height="1" fill="#D4A574"/>',
            '<rect x="3" y="11" width="18" height="1" fill="#7A5236"/>',
            '<rect x="5" y="11" width="14" height="1" fill="#D4A574"/>',
            '<rect x="11" y="11" width="2" height="1" fill="#3D2817"/>',
            '<rect x="4" y="12" width="16" height="1" fill="#7A5236"/>',
            '<rect x="6" y="12" width="12" height="1" fill="#D4A574"/>',
            '<rect x="9" y="12" width="6" height="1" fill="#3D2817"/>',
            '<rect x="5" y="13" width="14" height="1" fill="#7A5236"/>',
            '<rect x="7" y="13" width="10" height="1" fill="#D4A574"/>',
            '<rect x="6" y="14" width="12" height="1" fill="#7A5236"/>',
            '<rect x="5" y="15" width="14" height="1" fill="#7A5236"/>',
            '<rect x="4" y="16" width="16" height="1" fill="#7A5236"/>',
            '<rect x="6" y="16" width="12" height="1" fill="#D4A574"/>',
            '<rect x="4" y="17" width="16" height="1" fill="#7A5236"/>',
            '<rect x="6" y="17" width="12" height="1" fill="#D4A574"/>',
            '<rect x="4" y="18" width="16" height="1" fill="#7A5236"/>',
            '<rect x="7" y="18" width="10" height="1" fill="#D4A574"/>',
            '<rect x="3" y="19" width="2" height="1" fill="#7A5236"/>',
            '<rect x="19" y="19" width="2" height="1" fill="#7A5236"/>',
            '<rect x="5" y="19" width="14" height="1" fill="#7A5236"/>',
            '<rect x="2" y="20" width="3" height="2" fill="#7A5236"/>',
            '<rect x="19" y="20" width="3" height="2" fill="#7A5236"/>',
            '<rect x="6" y="20" width="4" height="2" fill="#7A5236"/>',
            '<rect x="14" y="20" width="4" height="2" fill="#7A5236"/>'
        ));
    }

    // ============ VARIANT COLOR SWAP TABLES ============
    // Each entry returns the source-color → replacement-color pairs the
    // Renderer applies via _replaceColor() to transform the base sprite.
    // Format: returns three pairs (from1,to1,from2,to2,from3,to3) — pass
    // empty strings for swaps that don't apply.

    function variantSwaps(uint8 speciesIdx, uint8 variantIdx)
        external
        pure
        returns (string memory f1, string memory t1, string memory f2, string memory t2, string memory f3, string memory t3, string memory f4, string memory t4)
    {
        if (speciesIdx == 0) {
            // Dog: A87D4A (dark), D4A574 (main), F4D9A8 (light)
            if (variantIdx == 1) return ("#A87D4A","#3D2817","#D4A574","#1A1A1F","#F4D9A8","#fff","","");
            if (variantIdx == 2) return ("#A87D4A","#9CA3AF","#D4A574","#fff","#F4D9A8","#E5E7EB","","");
            if (variantIdx == 3) return ("#A87D4A","#B8860B","#D4A574","#FFD700","#F4D9A8","#FFF4B5","","");
            return ("","","","","","","","");
        }
        if (speciesIdx == 1) {
            // Cat: E8843D (main), FFB084 (ear inside), FFE8D1 (belly), A04F1F (stripes)
            if (variantIdx == 1) return ("#E8843D","#1A1A1F","#FFB084","#4A4A50","#FFE8D1","#E5E7EB","#A04F1F","#1A0A0A");
            if (variantIdx == 2) return ("#E8843D","#fff","#FFB084","#E5E7EB","#FFE8D1","#fff","#A04F1F","#9CA3AF");
            if (variantIdx == 3) return ("#E8843D","#F4E4A0","#FFB084","#E8D9A0","#A04F1F","#7C4A1F","","");
            if (variantIdx == 4) return ("#E8843D","#6B21A8","#FFB084","#C084FC","#FFE8D1","#F3E8FF","#A04F1F","#4C1D95");
            return ("","","","","","","","");
        }
        if (speciesIdx == 2) {
            // Frog: 5BB041 (main), A4D693 (belly)
            if (variantIdx == 1) return ("#5BB041","#3D7A2D","#A4D693","#6BA84E","","","","");
            if (variantIdx == 2) return ("#5BB041","#FBBF24","#A4D693","#FCD34D","","","","");
            if (variantIdx == 3) return ("#5BB041","#3B82F6","#A4D693","#93C5FD","","","","");
            if (variantIdx == 4) return ("#5BB041","#FFE4E6","#A4D693","#fff","","","","");
            if (variantIdx == 5) return ("#5BB041","#DC2626","#A4D693","#FCA5A5","","","","");
            if (variantIdx == 6) return ("#5BB041","#FFD700","#A4D693","#FFF4B5","","","","");
            return ("","","","","","","","");
        }
        if (speciesIdx == 3) {
            // Bear: 7C4A1F (main), 3D2817 (ear), E8C9A0 (belly), A86B2D (feet)
            if (variantIdx == 1) return ("#7C4A1F","#1A1A1F","#3D2817","#4A4A50","#E8C9A0","#4A4A50","#A86B2D","#3D2817");
            if (variantIdx == 2) return ("#7C4A1F","#fff","#3D2817","#E5E7EB","#E8C9A0","#E5E7EB","#A86B2D","#E5E7EB");
            if (variantIdx == 3) return ("#7C4A1F","#FFD700","#3D2817","#B8860B","#E8C9A0","#FFF4B5","#A86B2D","#B8860B");
            return ("","","","","","","","");
        }
        if (speciesIdx == 4) {
            // Penguin: 6BA6E8 (main), FAF5E6 (belly)
            if (variantIdx == 1) return ("#6BA6E8","#1A1A1F","","","","","","");
            if (variantIdx == 2) return ("#6BA6E8","#FF8FA3","","","","","","");
            if (variantIdx == 3) return ("#6BA6E8","#fff","#FAF5E6","#FFFBEB","","","","");
            if (variantIdx == 4) return ("#6BA6E8","#86EFAC","","","","","","");
            if (variantIdx == 5) return ("#6BA6E8","#FFD700","#FAF5E6","#FFF4B5","","","","");
            return ("","","","","","","","");
        }
        // Ape: 7A5236 (main), D4A574 (face mask)
        if (variantIdx == 1) return ("#7A5236","#1A1A1F","#D4A574","#4A4A50","","","","");
        if (variantIdx == 2) return ("#7A5236","#fff","#D4A574","#E5E7EB","","","","");
        if (variantIdx == 3) return ("#7A5236","#9CA3AF","#D4A574","#E5E7EB","","","","");
        if (variantIdx == 4) return ("#7A5236","#DC2626","#D4A574","#FCA5A5","","","","");
        if (variantIdx == 5) return ("#7A5236","#6B21A8","#D4A574","#C084FC","","","","");
        return ("","","","","","","","");
    }
}
