// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title SpriteData
 * @notice Read-only data contract storing all trait pixel data for Onchainimals.
 *         Smaller trait pools (capes, backgrounds, effects, names, weighted picks)
 *         live here. Species sprites + headwear + weapons + 1/1s are split
 *         into companion contracts to stay under Ethereum's 24KB bytecode limit.
 *
 * @dev Layout:
 *   - SpriteData (this file)        — picks, names, capes, backgrounds, effects
 *   - SpriteDataSpecies (companion) — 6 species sprites + body variant swaps
 *   - SpriteDataHeadwear (companion)— 27 headwear items
 *   - SpriteDataWeapons (companion) — 18 weapons
 *   - SpriteDataIcons (companion)   — 5 one-of-one sprites
 *
 *   Renderer holds references to all of them and orchestrates the SVG composition.
 */
contract SpriteData {

    // ============ NAMES ============

    function speciesName(uint8 idx) external pure returns (string memory) {
        if (idx == 0) return "Dog";
        if (idx == 1) return "Cat";
        if (idx == 2) return "Frog";
        if (idx == 3) return "Bear";
        if (idx == 4) return "Penguin";
        return "Ape";
    }

    function bodyVariantName(uint8 speciesIdx, uint8 variantIdx) external pure returns (string memory) {
        if (speciesIdx == 0) { // Dog
            if (variantIdx == 0) return "Tan";
            if (variantIdx == 1) return "Black";
            if (variantIdx == 2) return "White";
            return "Gold";
        }
        if (speciesIdx == 1) { // Cat
            if (variantIdx == 0) return "Orange Tabby";
            if (variantIdx == 1) return "Black";
            if (variantIdx == 2) return "White";
            if (variantIdx == 3) return "Siamese";
            return "Cosmic";
        }
        if (speciesIdx == 2) { // Frog
            if (variantIdx == 0) return "Green";
            if (variantIdx == 1) return "Toad";
            if (variantIdx == 2) return "Yellow";
            if (variantIdx == 3) return "Poison Blue";
            if (variantIdx == 4) return "Albino";
            if (variantIdx == 5) return "Red Dart";
            return "Golden";
        }
        if (speciesIdx == 3) { // Bear
            if (variantIdx == 0) return "Brown";
            if (variantIdx == 1) return "Black";
            if (variantIdx == 2) return "Polar (Frank Frank)";
            return "Gold";
        }
        if (speciesIdx == 4) { // Penguin
            if (variantIdx == 0) return "Blue";
            if (variantIdx == 1) return "Emperor";
            if (variantIdx == 2) return "Pink";
            if (variantIdx == 3) return "Albino";
            if (variantIdx == 4) return "Mint";
            return "Gold";
        }
        // Ape
        if (variantIdx == 0) return "Brown";
        if (variantIdx == 1) return "Black";
        if (variantIdx == 2) return "White";
        if (variantIdx == 3) return "Silver";
        if (variantIdx == 4) return "Red";
        return "Cosmic";
    }

    function headwearName(uint8 idx) external pure returns (string memory) {
        if (idx == 0) return "None";
        if (idx == 1) return "Red Bandana";
        if (idx == 2) return "Blue Bandana";
        if (idx == 3) return "Green Bandana";
        if (idx == 4) return "Hard Hat";
        if (idx == 5) return "Bronze Med Helm";
        if (idx == 6) return "Pumpkin Helmet";
        if (idx == 7) return "Sleeping Cap";
        if (idx == 8) return "Wizard hat (g)";
        if (idx == 9) return "Pirate Tricorne";
        if (idx == 10) return "Robin Hood Hat";
        if (idx == 11) return "Bunny Ears";
        if (idx == 12) return "Helm of Neitiznot";
        if (idx == 13) return "Dragon Med Helm";
        if (idx == 14) return "Black Mask";
        if (idx == 15) return "Halo";
        if (idx == 16) return "Santa Hat";
        if (idx == 17) return "Red H'ween Mask";
        if (idx == 18) return "Blue H'ween Mask";
        if (idx == 19) return "Green H'ween Mask";
        if (idx == 20) return "Black H'ween Mask";
        if (idx == 21) return "Purple Partyhat";
        if (idx == 22) return "White Partyhat";
        if (idx == 23) return "Red Partyhat";
        if (idx == 24) return "Blue Partyhat";
        if (idx == 25) return "Green Partyhat";
        return "Yellow Partyhat";
    }

    function weaponName(uint8 idx) external pure returns (string memory) {
        if (idx == 0) return "None";
        if (idx == 1) return "Iron Scimitar";
        if (idx == 2) return "Bronze Scimitar";
        if (idx == 3) return "Yo-yo";
        if (idx == 4) return "Tinderbox";
        if (idx == 5) return "Magic Shortbow";
        if (idx == 6) return "Adamant Scimitar";
        if (idx == 7) return "Rune Scimitar";
        if (idx == 8) return "Dragon Dagger";
        if (idx == 9) return "Granite Maul";
        if (idx == 10) return "Pickaxe";
        if (idx == 11) return "Dragon Spear";
        if (idx == 12) return "Dragon Claws";
        if (idx == 13) return "Bandos Godsword";
        if (idx == 14) return "Abyssal Whip";
        if (idx == 15) return "Saradomin Sword";
        if (idx == 16) return "Dragon Scimitar";
        if (idx == 17) return "Twisted Bow";
        return "Scythe of Vitur";
    }

    function capeName(uint8 idx) external pure returns (string memory) {
        if (idx == 0) return "None";
        if (idx == 1) return "Attack Cape";
        if (idx == 2) return "Strength Cape";
        if (idx == 3) return "Magic Cape";
        if (idx == 4) return "Slayer Cape";
        if (idx == 5) return "Fishing Cape";
        if (idx == 6) return "Woodcutting Cape";
        if (idx == 7) return "Fire Cape";
        if (idx == 8) return "Max Cape";
        return "Infernal Cape";
    }

    function backgroundName(uint8 idx) external pure returns (string memory) {
        if (idx == 0) return "Default";
        if (idx == 1) return "Lumbridge";
        if (idx == 2) return "Falador";
        if (idx == 3) return "Camelot";
        if (idx == 4) return "Ardougne";
        if (idx == 5) return "Rellekka";
        if (idx == 6) return "Tree Gnome Village";
        if (idx == 7) return "Edgeville";
        if (idx == 8) return "Karamja";
        if (idx == 9) return "Ice Plateau";
        if (idx == 10) return "Grand Exchange";
        if (idx == 11) return "Wilderness";
        return "Inferno";
    }

    function effectName(uint8 idx) external pure returns (string memory) {
        if (idx == 0) return "None";
        if (idx == 1) return "Eye Glow";
        if (idx == 2) return "Fire Aura";
        return "Sparkles";
    }

    // ============ WEIGHTED PICKS ============
    // Total weights mirror random100.html / mint.html (post-rebalance).

    function pickHeadwear(uint256 seed) external pure returns (uint8 idx, uint8 tier) {
        // Sleeping Cap (40) + Santa Hat (2) doubled to compensate for removal on frog/ape/penguin
        // Total weight: ~287
        uint256 r = seed % 287;
        if (r < 50) return (0, 0);          // None
        if (r < 80) return (1, 0);          // Red Bandana
        if (r < 110) return (2, 0);         // Blue Bandana
        if (r < 135) return (3, 0);         // Green Bandana
        if (r < 155) return (4, 0);         // Hard Hat
        if (r < 177) return (5, 0);         // Bronze Med Helm
        if (r < 202) return (6, 1);         // Pumpkin Helmet
        if (r < 242) return (7, 1);         // Sleeping Cap (40)
        if (r < 254) return (8, 1);         // Wizard hat (g)
        if (r < 257) return (9, 2);         // Pirate Tricorne
        if (r < 259) return (10, 2);        // Robin Hood Hat
        if (r < 261) return (11, 2);        // Bunny Ears
        if (r < 265) return (12, 2);        // Helm of Neitiznot
        if (r < 270) return (13, 2);        // Dragon Med Helm
        if (r < 274) return (14, 2);        // Black Mask
        if (r < 275) return (15, 3);        // Halo
        if (r < 277) return (16, 3);        // Santa Hat (2)
        if (r < 278) return (17, 3);        // Red H'ween Mask
        if (r < 279) return (18, 3);        // Blue H'ween Mask
        if (r < 280) return (19, 3);        // Green H'ween Mask
        if (r < 281) return (20, 3);        // Black H'ween Mask
        if (r < 282) return (21, 4);        // Purple Partyhat
        if (r < 283) return (22, 4);        // White Partyhat
        if (r < 284) return (23, 4);        // Red Partyhat
        if (r < 285) return (24, 4);        // Blue Partyhat
        if (r < 286) return (25, 4);        // Green Partyhat
        return (26, 4);                     // Yellow Partyhat
    }

    function pickWeapon(uint256 seed) external pure returns (uint8 idx, uint8 tier) {
        // None 150 + Iron 35 + Bronze 30 + Yoyo 25 + Tinderbox 20 + MagicSB 25
        // + Adamant 3 + Rune 2 + DDS 2 + GranMaul 4 + Pickaxe 3
        // + DragSpear 0.5 + DragClaws 1 + BGS 1 + Whip 1 + SaraSword 0.5
        // + DragScim 0.3 + Tbow 0.1 + Scythe 0.1 ≈ 303
        uint256 r = seed % 303;
        if (r < 150) return (0, 0);
        if (r < 185) return (1, 0);
        if (r < 215) return (2, 0);
        if (r < 240) return (3, 1);
        if (r < 260) return (4, 1);
        if (r < 285) return (5, 1);
        if (r < 288) return (6, 2);
        if (r < 290) return (7, 2);
        if (r < 292) return (8, 2);
        if (r < 296) return (9, 2);
        if (r < 299) return (10, 2);
        if (r < 300) return (11, 3);  // ~0.5, treated as 1
        if (r < 301) return (12, 3);
        if (r < 302) return (13, 3);
        if (r < 303) return (14, 3);
        return (15, 3);
    }

    function pickCape(uint256 seed) external pure returns (uint8 idx, uint8 tier) {
        // None 130 + Attack 12 + Str 11 + Magic 11 + Slayer 10 + Fishing 10
        // + Wood 10 + Fire 5 + Max 3 + Infernal 0.3 ≈ 202
        uint256 r = seed % 202;
        if (r < 130) return (0, 0);
        if (r < 142) return (1, 1);
        if (r < 153) return (2, 1);
        if (r < 164) return (3, 1);
        if (r < 174) return (4, 1);
        if (r < 184) return (5, 1);
        if (r < 194) return (6, 1);
        if (r < 199) return (7, 3);
        if (r < 202) return (8, 3);
        return (9, 4);
    }

    function pickBackground(uint256 seed) external pure returns (uint8 idx, uint8 tier) {
        // Default 25 + Lumb 15 + Fal 13 + Cam 13 + Ardy 13 + Rellekka 18
        // + TreeGnome 18 + Edge 12 + Kar 5 + Ice 6 + GE 2 + Wildy 1 + Inferno 1 = 142
        uint256 r = seed % 142;
        if (r < 25) return (0, 0);
        if (r < 40) return (1, 0);
        if (r < 53) return (2, 0);
        if (r < 66) return (3, 0);
        if (r < 79) return (4, 0);
        if (r < 97) return (5, 1);    // Rellekka
        if (r < 115) return (6, 1);   // Tree Gnome Village
        if (r < 127) return (7, 1);   // Edgeville
        if (r < 132) return (8, 2);   // Karamja
        if (r < 138) return (9, 2);   // Ice Plateau
        if (r < 140) return (10, 3);  // GE
        if (r < 141) return (11, 4);  // Wilderness
        return (12, 4);                // Inferno
    }

    function pickEffect(uint256 seed) external pure returns (uint8 idx, uint8 tier) {
        // None 130 + EyeGlow 40 + FireAura 3 + Sparkles 0.5 ≈ 174
        uint256 r = seed % 174;
        if (r < 130) return (0, 0);
        if (r < 170) return (1, 1);
        if (r < 173) return (2, 3);
        return (3, 4);
    }

    function pickBodyVariant(uint8 speciesIdx, uint256 seed) external pure returns (uint8 idx, uint8 tier) {
        // Body variant pools — all species default ≈ 200 weight, mythic ≈ 0.3-1
        if (speciesIdx == 0) { // Dog: Tan 200, Black 5, White 5, Gold 1 ≈ 211
            uint256 r = seed % 211;
            if (r < 200) return (0, 0);
            if (r < 205) return (1, 2);
            if (r < 210) return (2, 2);
            return (3, 4);
        }
        if (speciesIdx == 1) { // Cat: Orange 200, Black 5, White 5, Siamese 2, Cosmic 0.5 ≈ 213
            uint256 r = seed % 213;
            if (r < 200) return (0, 0);
            if (r < 205) return (1, 2);
            if (r < 210) return (2, 2);
            if (r < 212) return (3, 3);
            return (4, 4);
        }
        if (speciesIdx == 2) { // Frog: Green 200, Toad 5, Yellow 3, Blue 2, Albino 1, Red 1, Gold 0.5 ≈ 213
            uint256 r = seed % 213;
            if (r < 200) return (0, 0);
            if (r < 205) return (1, 2);
            if (r < 208) return (2, 2);
            if (r < 210) return (3, 3);
            if (r < 211) return (4, 3);
            if (r < 212) return (5, 3);
            return (6, 4);
        }
        if (speciesIdx == 3) { // Bear: Brown 200, Black 8, Polar 3, Gold 0.5 ≈ 212
            uint256 r = seed % 212;
            if (r < 200) return (0, 0);
            if (r < 208) return (1, 2);
            if (r < 211) return (2, 3);
            return (3, 4);
        }
        if (speciesIdx == 4) { // Penguin: Blue 200, Emperor 5, Pink 5, Albino 2, Mint 1, Gold 0.3 ≈ 213
            uint256 r = seed % 213;
            if (r < 200) return (0, 0);
            if (r < 205) return (1, 2);
            if (r < 210) return (2, 2);
            if (r < 212) return (3, 3);
            return (4, 4);
        }
        // Ape: Brown 200, Black 5, White 5, Silver 2, Red 1, Cosmic 0.3 ≈ 213
        uint256 r2 = seed % 213;
        if (r2 < 200) return (0, 0);
        if (r2 < 205) return (1, 2);
        if (r2 < 210) return (2, 2);
        if (r2 < 212) return (3, 3);
        if (r2 < 213) return (4, 3);
        return (5, 4);
    }

    // ============ INDEX LOOKUPS FOR HARD-CODED ITEMS ============

    function partyhatHeadwearIdx(uint8 colorIdx) external pure returns (uint8) {
        // colorIdx 0=Purple, 1=White, 2=Red, 3=Blue, 4=Green, 5=Yellow
        return 21 + colorIdx;
    }

    function dragonDaggerWeaponIdx() external pure returns (uint8) {
        return 8;
    }

    function dragonSpearWeaponIdx() external pure returns (uint8) {
        return 11;
    }

    // ============ CAPES (smaller pool — inlined here) ============
    // All cape positions are cols 18-22, rows 9-17, behind species sprite.

    function capeSVG(uint8 idx) external pure returns (string memory) {
        if (idx == 0) return "";
        if (idx == 1) { // Attack Cape (red + gold trim + white pixel)
            return '<rect x="18" y="9" width="5" height="1" fill="#FFD700"/><rect x="18" y="10" width="5" height="3" fill="#DC2626"/><rect x="20" y="13" width="1" height="1" fill="#fff"/><rect x="18" y="13" width="5" height="4" fill="#DC2626"/><rect x="18" y="17" width="5" height="1" fill="#FFD700"/>';
        }
        if (idx == 2) { // Strength Cape (yellow + brown trim)
            return '<rect x="18" y="9" width="5" height="1" fill="#92400E"/><rect x="18" y="10" width="5" height="3" fill="#FBBF24"/><rect x="20" y="13" width="1" height="1" fill="#92400E"/><rect x="18" y="13" width="5" height="4" fill="#FBBF24"/><rect x="18" y="17" width="5" height="1" fill="#92400E"/>';
        }
        if (idx == 3) { // Magic Cape (blue + purple trim + white star)
            return '<rect x="18" y="9" width="5" height="1" fill="#A855F7"/><rect x="18" y="10" width="5" height="3" fill="#3B82F6"/><rect x="20" y="13" width="1" height="1" fill="#fff"/><rect x="18" y="13" width="5" height="4" fill="#3B82F6"/><rect x="18" y="17" width="5" height="1" fill="#A855F7"/>';
        }
        if (idx == 4) { // Slayer Cape (black + grey trim + white skull)
            return '<rect x="18" y="9" width="5" height="1" fill="#4A4A50"/><rect x="18" y="10" width="5" height="3" fill="#1A1A1F"/><rect x="20" y="13" width="1" height="1" fill="#fff"/><rect x="18" y="13" width="5" height="4" fill="#1A1A1F"/><rect x="18" y="17" width="5" height="1" fill="#4A4A50"/>';
        }
        if (idx == 5) { // Fishing Cape (cyan + white trim)
            return '<rect x="18" y="9" width="5" height="1" fill="#fff"/><rect x="18" y="10" width="5" height="7" fill="#06B6D4"/><rect x="18" y="17" width="5" height="1" fill="#fff"/>';
        }
        if (idx == 6) { // Woodcutting Cape (green + brown trim)
            return '<rect x="18" y="9" width="5" height="1" fill="#7C4A1F"/><rect x="18" y="10" width="5" height="7" fill="#15803D"/><rect x="18" y="17" width="5" height="1" fill="#7C4A1F"/>';
        }
        if (idx == 7) { // Fire Cape (red/orange alternating)
            return '<rect x="18" y="9" width="5" height="1" fill="#DC2626"/><rect x="18" y="10" width="5" height="1" fill="#F97316"/><rect x="18" y="11" width="5" height="1" fill="#DC2626"/><rect x="18" y="12" width="5" height="1" fill="#F97316"/><rect x="18" y="13" width="5" height="1" fill="#DC2626"/><rect x="18" y="14" width="5" height="1" fill="#F97316"/><rect x="18" y="15" width="5" height="1" fill="#DC2626"/><rect x="18" y="16" width="5" height="1" fill="#F97316"/><rect x="18" y="17" width="5" height="1" fill="#DC2626"/>';
        }
        if (idx == 8) { // Max Cape (rainbow bands)
            return '<rect x="18" y="9" width="5" height="1" fill="#DC2626"/><rect x="18" y="10" width="5" height="1" fill="#F97316"/><rect x="18" y="11" width="5" height="1" fill="#FBBF24"/><rect x="18" y="12" width="5" height="1" fill="#22C55E"/><rect x="18" y="13" width="5" height="1" fill="#3B82F6"/><rect x="18" y="14" width="5" height="1" fill="#A855F7"/><rect x="18" y="15" width="5" height="1" fill="#DC2626"/><rect x="18" y="16" width="5" height="1" fill="#F97316"/><rect x="18" y="17" width="5" height="1" fill="#22C55E"/>';
        }
        // Infernal Cape
        return '<rect x="18" y="9" width="5" height="1" fill="#1A0A0A"/><rect x="18" y="10" width="5" height="1" fill="#FBBF24"/><rect x="18" y="11" width="5" height="1" fill="#1A0A0A"/><rect x="18" y="12" width="5" height="1" fill="#DC2626"/><rect x="18" y="13" width="5" height="1" fill="#1A0A0A"/><rect x="18" y="14" width="5" height="1" fill="#F97316"/><rect x="18" y="15" width="5" height="1" fill="#1A0A0A"/><rect x="18" y="16" width="5" height="1" fill="#FBBF24"/><rect x="18" y="17" width="5" height="1" fill="#DC2626"/>';
    }

    // ============ BACKGROUNDS ============

    function backgroundBGColor(uint8 idx, uint8 speciesIdx) external pure returns (string memory) {
        if (idx == 0) {
            // Default species pastel
            if (speciesIdx == 0) return "#FCE8D4";
            if (speciesIdx == 1) return "#FFE3F0";
            if (speciesIdx == 2) return "#D4F4D4";
            if (speciesIdx == 3) return "#F5E6D3";
            if (speciesIdx == 4) return "#D9F2FA";
            return "#EFE4D0";
        }
        if (idx == 1) return "#86EFAC"; // Lumbridge
        if (idx == 2) return "#B5C6D6"; // Falador
        if (idx == 3) return "#86A878"; // Camelot
        if (idx == 4) return "#C8AC7A"; // Ardougne
        if (idx == 5) return "#7DD3FC"; // Rellekka
        if (idx == 6) return "#3F6B2A"; // Tree Gnome Village
        if (idx == 7) return "#6B5544"; // Edgeville
        if (idx == 8) return "#DD6E32"; // Karamja
        if (idx == 9) return "#E0F2FE"; // Ice Plateau
        if (idx == 10) return "#9CA3AF"; // GE
        if (idx == 11) return "#7F1D1D"; // Wilderness
        return "#1A0A0A";               // Inferno
    }

    function backgroundOverlay(uint8 idx) external pure returns (string memory) {
        if (idx == 0) return "";
        if (idx == 1) return '<rect x="0" y="20" width="24" height="4" fill="#15803D"/>';
        if (idx == 2) return '<rect x="0" y="20" width="24" height="4" fill="#9CA3AF"/><rect x="3" y="21" width="2" height="1" fill="#fff"/><rect x="18" y="21" width="3" height="1" fill="#fff"/>';
        if (idx == 3) return '<rect x="0" y="20" width="24" height="4" fill="#5C7050"/><rect x="11" y="20" width="2" height="1" fill="#3B82F6"/>';
        if (idx == 4) return '<rect x="0" y="20" width="24" height="4" fill="#8A7349"/>';
        if (idx == 5) return '<rect x="0" y="20" width="24" height="4" fill="#E8D9A0"/><rect x="0" y="22" width="24" height="2" fill="#C8AC7A"/><rect x="3" y="21" width="3" height="1" fill="#6B7280"/><rect x="14" y="21" width="2" height="1" fill="#6B7280"/><rect x="19" y="22" width="2" height="1" fill="#4B5563"/>';
        if (idx == 6) return '<rect x="0" y="20" width="24" height="4" fill="#1F3D1B"/><rect x="0" y="0" width="2" height="20" fill="#7C4A1F"/><rect x="22" y="0" width="2" height="20" fill="#7C4A1F"/><rect x="0" y="0" width="24" height="2" fill="#166534"/><rect x="6" y="0" width="2" height="2" fill="#22C55E"/><rect x="16" y="0" width="2" height="2" fill="#22C55E"/>';
        if (idx == 7) return '<rect x="0" y="0" width="24" height="1" fill="#5A4533"/><rect x="0" y="6" width="24" height="1" fill="#5A4533"/><rect x="0" y="12" width="24" height="1" fill="#5A4533"/><rect x="0" y="18" width="24" height="1" fill="#5A4533"/><rect x="0" y="20" width="24" height="4" fill="#5A4533"/>';
        if (idx == 8) return '<rect x="0" y="20" width="24" height="4" fill="#9A3412"/>';
        if (idx == 9) return '<rect x="0" y="20" width="24" height="4" fill="#fff"/><rect x="2" y="22" width="5" height="1" fill="#BAE6FD"/><rect x="14" y="21" width="6" height="1" fill="#BAE6FD"/><rect x="9" y="2" width="1" height="1" fill="#fff"/><rect x="3" y="5" width="1" height="1" fill="#fff"/><rect x="17" y="7" width="1" height="1" fill="#fff"/><rect x="20" y="3" width="1" height="1" fill="#fff"/>';
        if (idx == 10) return '<rect x="0" y="3" width="24" height="1" fill="#6B7280"/><rect x="0" y="9" width="24" height="1" fill="#6B7280"/><rect x="0" y="15" width="24" height="1" fill="#6B7280"/><rect x="0" y="21" width="24" height="1" fill="#6B7280"/><rect x="3" y="0" width="1" height="24" fill="#6B7280"/><rect x="11" y="0" width="1" height="24" fill="#6B7280"/><rect x="19" y="0" width="1" height="24" fill="#6B7280"/>';
        if (idx == 11) return '<rect x="0" y="0" width="24" height="6" fill="#991B1B"/><rect x="20" y="1" width="3" height="1" fill="#F4F4F5"/><rect x="19" y="2" width="5" height="1" fill="#F4F4F5"/><rect x="20" y="2" width="1" height="1" fill="#1A0A0A"/><rect x="22" y="2" width="1" height="1" fill="#1A0A0A"/>';
        return '<rect x="0" y="0" width="24" height="3" fill="#7F1D1D"/><rect x="0" y="3" width="24" height="2" fill="#DC2626"/><rect x="0" y="5" width="24" height="2" fill="#F97316"/>';
    }

    // ============ EFFECTS ============

    function effectSVG(uint8 idx) external pure returns (string memory) {
        if (idx == 0) return "";
        if (idx == 1) return '<rect x="22" y="3" width="1" height="1" fill="#FFD700"/><rect x="21" y="4" width="3" height="1" fill="#FFD700"/><rect x="22" y="5" width="1" height="1" fill="#FFD700"/><rect x="1" y="14" width="1" height="1" fill="#FFD700"/><rect x="0" y="15" width="3" height="1" fill="#FFD700"/><rect x="1" y="16" width="1" height="1" fill="#FFD700"/>';
        if (idx == 2) return '<rect x="0" y="15" width="2" height="1" fill="#F97316"/><rect x="0" y="16" width="2" height="1" fill="#FBBF24"/><rect x="22" y="15" width="2" height="1" fill="#FBBF24"/><rect x="22" y="16" width="2" height="1" fill="#DC2626"/><rect x="3" y="21" width="2" height="1" fill="#F97316"/><rect x="11" y="20" width="3" height="1" fill="#DC2626"/><rect x="18" y="22" width="3" height="1" fill="#FBBF24"/>';
        return '<rect x="3" y="4" width="1" height="1" fill="#FFD700"/><rect x="2" y="5" width="3" height="1" fill="#FFD700"/><rect x="3" y="6" width="1" height="1" fill="#FFD700"/><rect x="20" y="7" width="1" height="1" fill="#fff"/><rect x="19" y="8" width="3" height="1" fill="#fff"/><rect x="20" y="9" width="1" height="1" fill="#fff"/><rect x="1" y="14" width="1" height="1" fill="#FFD700"/><rect x="22" y="17" width="1" height="1" fill="#FFD700"/>';
    }
}
