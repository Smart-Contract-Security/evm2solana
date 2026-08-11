// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Types} from "./Types.sol";

/// @title Traits — trait rolling, weighting tables, tier-exclusive gating
/// @notice Pure functions. No storage. Seeded by keccak256(provenanceSeed, tokenId, slot).
library Traits {
    // ------------------------------------------------------------------
    // Tier roll
    // ------------------------------------------------------------------

    /// @notice Roll a tier based on mint drop weights, with Mythic cap fallback.
    /// @param rng Random seed for this attempt
    /// @param mythicCount Current minted count of Mythic tokens
    /// @return tier Tier index 0..5
    function rollTier(uint256 rng, uint256 mythicCount) internal pure returns (uint8 tier) {
        uint256 roll = rng % 10_000;
        uint256 cum = Types.DROP_COMMON;
        if (roll < cum) return Types.TIER_COMMON;
        cum += Types.DROP_UNCOMMON;
        if (roll < cum) return Types.TIER_UNCOMMON;
        cum += Types.DROP_RARE;
        if (roll < cum) return Types.TIER_RARE;
        cum += Types.DROP_EPIC;
        if (roll < cum) return Types.TIER_EPIC;
        cum += Types.DROP_LEGENDARY;
        if (roll < cum) return Types.TIER_LEGENDARY;
        // Otherwise mythic, but cascade to Legendary if cap reached.
        if (mythicCount >= Types.MYTHIC_CAP) return Types.TIER_LEGENDARY;
        return Types.TIER_MYTHIC;
    }

    // ------------------------------------------------------------------
    // Variant rolls per slot
    // ------------------------------------------------------------------

    /// @notice Roll all 8 traits for a token.
    /// @param tier Tier index
    /// @param baseSeed Token-level seed = keccak256(provenanceSeed, tokenId)
    /// @return d Populated TokenData (without ascensionCount, mintPriceSnapshotBps)
    function rollAll(uint8 tier, uint256 baseSeed) public pure returns (Types.TokenData memory d) {
        d.tier         = tier;
        d.hoodShape    = rollHood(tier, _slot(baseSeed, Types.SLOT_HOOD_SHAPE));
        d.faceInside   = rollFace(tier, _slot(baseSeed, Types.SLOT_FACE_INSIDE));
        d.obolPosition = rollObol(tier, _slot(baseSeed, Types.SLOT_OBOL_POS));
        d.coinMark     = rollCoinMark(tier, _slot(baseSeed, Types.SLOT_COIN_MARK));
        d.topSigil     = rollSigil(tier, _slot(baseSeed, Types.SLOT_TOP_SIGIL));
        d.background   = rollBackground(tier, _slot(baseSeed, Types.SLOT_BACKGROUND));
        d.posture      = rollPosture(tier, _slot(baseSeed, Types.SLOT_POSTURE));
        d.cloakDetail  = rollCloakDetail(tier, _slot(baseSeed, Types.SLOT_CLOAK_DETAIL));
    }

    function _slot(uint256 baseSeed, uint8 slot) private pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(baseSeed, slot)));
    }

    // ------------------------------------------------------------------
    // Slot tables
    // Each function returns a variant index 0..N-1.
    // Tier-exclusive variants gated inside (e.g., Mythic-only Third Eye).
    // ------------------------------------------------------------------

    // Hood Shape: 6 base variants. Higher tiers add tier-exclusive shapes.
    // 0=Plain  1=Peaked  2=PulledBack  3=ArmsOut  4=Tattered  5=Bound
    // 6=Crowned (Legendary+) 7=Halo'd (Mythic only)
    function rollHood(uint8 tier, uint256 rng) internal pure returns (uint8) {
        uint256 r = rng % 100;
        if (tier == Types.TIER_MYTHIC) {
            if (r < 30) return 7;          // Halo'd (Mythic exclusive)
            if (r < 60) return 6;          // Crowned
            if (r < 80) return 4;          // Tattered
            return 5;                      // Bound
        }
        if (tier == Types.TIER_LEGENDARY) {
            if (r < 25) return 6;          // Crowned
            if (r < 55) return 4;          // Tattered
            if (r < 80) return 5;          // Bound
            return 2;                      // PulledBack
        }
        if (tier == Types.TIER_EPIC) {
            if (r < 30) return 4;
            if (r < 60) return 5;
            if (r < 80) return 2;
            return 3;
        }
        if (tier == Types.TIER_RARE) {
            if (r < 25) return 4;
            if (r < 55) return 2;
            if (r < 80) return 3;
            return 1;
        }
        if (tier == Types.TIER_UNCOMMON) {
            if (r < 30) return 2;
            if (r < 60) return 1;
            if (r < 85) return 3;
            return 0;
        }
        // Common
        if (r < 40) return 0;
        if (r < 65) return 1;
        if (r < 85) return 2;
        return 3;
    }

    // Face Inside: 8 variants. Third Eye (7) is Mythic-only.
    // 0=TwoVoids  1=HollowGaze  2=Drowned  3=Sunken  4=Wide  5=Closed  6=Tearmark  7=ThirdEye (Mythic)
    function rollFace(uint8 tier, uint256 rng) internal pure returns (uint8) {
        uint256 r = rng % 100;
        if (tier == Types.TIER_MYTHIC) {
            if (r < 50) return 7;          // Third Eye (Mythic exclusive)
            if (r < 75) return 6;
            return 4;
        }
        if (tier == Types.TIER_LEGENDARY) {
            if (r < 30) return 6;
            if (r < 60) return 4;
            if (r < 80) return 2;
            return 3;
        }
        if (tier == Types.TIER_EPIC) {
            if (r < 25) return 6;
            if (r < 55) return 4;
            if (r < 80) return 3;
            return 2;
        }
        if (tier == Types.TIER_RARE) {
            if (r < 30) return 4;
            if (r < 60) return 3;
            if (r < 80) return 1;
            return 2;
        }
        if (tier == Types.TIER_UNCOMMON) {
            if (r < 35) return 1;
            if (r < 65) return 3;
            if (r < 85) return 5;
            return 0;
        }
        // Common
        if (r < 45) return 0;
        if (r < 70) return 1;
        if (r < 88) return 5;
        return 3;
    }

    // Obol Position: 5 variants.
    // 0=NoObol  1=HeldLeft  2=HeldCenter  3=Falling  4=Engulfed
    function rollObol(uint8 tier, uint256 rng) internal pure returns (uint8) {
        uint256 r = rng % 100;
        if (tier >= Types.TIER_LEGENDARY) {
            if (r < 35) return 4;          // Engulfed
            if (r < 65) return 3;          // Falling
            if (r < 85) return 2;
            return 1;
        }
        if (tier == Types.TIER_EPIC) {
            if (r < 30) return 3;
            if (r < 60) return 2;
            if (r < 85) return 1;
            return 0;
        }
        if (tier == Types.TIER_RARE) {
            if (r < 35) return 2;
            if (r < 70) return 1;
            if (r < 90) return 3;
            return 0;
        }
        if (tier == Types.TIER_UNCOMMON) {
            if (r < 45) return 1;
            if (r < 80) return 2;
            return 0;
        }
        // Common
        if (r < 55) return 0;
        if (r < 80) return 1;
        return 2;
    }

    // Coin Mark: 6 variants. Burning Brand (5) is Legendary+ exclusive.
    // 0=None  1=SingleEtch  2=DoubleEtch  3=Sigil  4=TripleEtch  5=BurningBrand (Legendary/Mythic)
    function rollCoinMark(uint8 tier, uint256 rng) internal pure returns (uint8) {
        uint256 r = rng % 1000;
        if (tier >= Types.TIER_LEGENDARY) {
            if (r < 400) return 5;         // Burning Brand
            if (r < 700) return 4;
            if (r < 870) return 3;
            return 2;
        }
        if (tier == Types.TIER_EPIC) {
            if (r < 350) return 4;
            if (r < 650) return 3;
            if (r < 850) return 2;
            return 1;
        }
        if (tier == Types.TIER_RARE) {
            if (r < 350) return 3;
            if (r < 650) return 2;
            if (r < 870) return 1;
            return 4;
        }
        if (tier == Types.TIER_UNCOMMON) {
            if (r < 450) return 1;
            if (r < 800) return 2;
            return 3;
        }
        // Common — example from SPEC: 50/22/15/9/3.5/0.5%
        if (r < 500) return 0;
        if (r < 720) return 1;
        if (r < 870) return 2;
        if (r < 960) return 3;
        if (r < 995) return 4;
        return 5; // very rare even on Common, but possible
    }

    // Top Sigil: 6 variants.
    // 0=None  1=Crescent  2=Cross  3=Spiral  4=Eye  5=LotusOfAsh (Mythic only)
    function rollSigil(uint8 tier, uint256 rng) internal pure returns (uint8) {
        uint256 r = rng % 100;
        if (tier == Types.TIER_MYTHIC) {
            if (r < 60) return 5;          // Lotus of Ash (Mythic exclusive)
            if (r < 85) return 4;
            return 3;
        }
        if (tier == Types.TIER_LEGENDARY) {
            if (r < 35) return 4;
            if (r < 65) return 3;
            if (r < 85) return 2;
            return 1;
        }
        if (tier == Types.TIER_EPIC) {
            if (r < 30) return 3;
            if (r < 60) return 2;
            if (r < 85) return 1;
            return 4;
        }
        if (tier == Types.TIER_RARE) {
            if (r < 40) return 2;
            if (r < 70) return 1;
            if (r < 90) return 3;
            return 0;
        }
        if (tier == Types.TIER_UNCOMMON) {
            if (r < 50) return 1;
            if (r < 85) return 0;
            return 2;
        }
        // Common
        if (r < 70) return 0;
        if (r < 90) return 1;
        return 2;
    }

    // Background: 6 variants.
    // 0=BoneWhite  1=AshGrey  2=Charcoal  3=RiverFog  4=EmberOrange (Legendary+)  5=GildedFog (Mythic only)
    function rollBackground(uint8 tier, uint256 rng) internal pure returns (uint8) {
        uint256 r = rng % 100;
        if (tier == Types.TIER_MYTHIC) {
            if (r < 70) return 5;
            return 4;
        }
        if (tier == Types.TIER_LEGENDARY) {
            if (r < 60) return 4;
            if (r < 85) return 2;
            return 3;
        }
        if (tier == Types.TIER_EPIC) {
            if (r < 40) return 3;
            if (r < 70) return 2;
            return 1;
        }
        if (tier == Types.TIER_RARE) {
            if (r < 45) return 3;
            if (r < 80) return 1;
            return 2;
        }
        if (tier == Types.TIER_UNCOMMON) {
            if (r < 40) return 1;
            if (r < 75) return 0;
            return 3;
        }
        // Common
        if (r < 55) return 0;
        if (r < 85) return 1;
        return 3;
    }

    // Posture: 4 variants.
    // 0=Standing  1=ArmsOut  2=Bowing  3=Ascending (Legendary+ exclusive)
    function rollPosture(uint8 tier, uint256 rng) internal pure returns (uint8) {
        uint256 r = rng % 100;
        if (tier >= Types.TIER_LEGENDARY) {
            if (r < 55) return 3;
            if (r < 85) return 1;
            return 2;
        }
        if (tier == Types.TIER_EPIC) {
            if (r < 45) return 1;
            if (r < 80) return 2;
            return 0;
        }
        if (tier == Types.TIER_RARE) {
            if (r < 50) return 1;
            if (r < 85) return 0;
            return 2;
        }
        if (tier == Types.TIER_UNCOMMON) {
            if (r < 45) return 0;
            if (r < 80) return 1;
            return 2;
        }
        if (r < 70) return 0;
        if (r < 90) return 1;
        return 2;
    }

    // Cloak Detail: 5 variants.
    // 0=Plain  1=Hatched  2=Tattered  3=Embered (Legendary+)  4=AshFlow (Mythic only)
    function rollCloakDetail(uint8 tier, uint256 rng) internal pure returns (uint8) {
        uint256 r = rng % 100;
        if (tier == Types.TIER_MYTHIC) {
            if (r < 60) return 4;
            if (r < 85) return 3;
            return 2;
        }
        if (tier == Types.TIER_LEGENDARY) {
            if (r < 55) return 3;
            if (r < 80) return 2;
            return 1;
        }
        if (tier == Types.TIER_EPIC) {
            if (r < 40) return 2;
            if (r < 75) return 1;
            return 0;
        }
        if (tier == Types.TIER_RARE) {
            if (r < 45) return 1;
            if (r < 80) return 2;
            return 0;
        }
        if (tier == Types.TIER_UNCOMMON) {
            if (r < 50) return 0;
            if (r < 85) return 1;
            return 2;
        }
        if (r < 60) return 0;
        if (r < 88) return 1;
        return 2;
    }

    // ------------------------------------------------------------------
    // Human-readable names for metadata attributes
    // ------------------------------------------------------------------

    function hoodName(uint8 v) internal pure returns (string memory) {
        if (v == 0) return "Plain";
        if (v == 1) return "Peaked";
        if (v == 2) return "Pulled Back";
        if (v == 3) return "Arms Out";
        if (v == 4) return "Tattered";
        if (v == 5) return "Bound";
        if (v == 6) return "Crowned";
        if (v == 7) return "Halo'd";
        return "Unknown";
    }

    function faceName(uint8 v) internal pure returns (string memory) {
        if (v == 0) return "Two Voids";
        if (v == 1) return "Hollow Gaze";
        if (v == 2) return "Drowned";
        if (v == 3) return "Sunken";
        if (v == 4) return "Wide";
        if (v == 5) return "Closed";
        if (v == 6) return "Tearmark";
        if (v == 7) return "Third Eye";
        return "Unknown";
    }

    function obolName(uint8 v) internal pure returns (string memory) {
        if (v == 0) return "No Obol";
        if (v == 1) return "Held Left";
        if (v == 2) return "Held Center";
        if (v == 3) return "Falling";
        if (v == 4) return "Engulfed";
        return "Unknown";
    }

    function coinMarkName(uint8 v) internal pure returns (string memory) {
        if (v == 0) return "None";
        if (v == 1) return "Single Etch";
        if (v == 2) return "Double Etch";
        if (v == 3) return "Sigil";
        if (v == 4) return "Triple Etch";
        if (v == 5) return "Burning Brand";
        return "Unknown";
    }

    function sigilName(uint8 v) internal pure returns (string memory) {
        if (v == 0) return "None";
        if (v == 1) return "Crescent";
        if (v == 2) return "Cross";
        if (v == 3) return "Spiral";
        if (v == 4) return "Eye";
        if (v == 5) return "Lotus of Ash";
        return "Unknown";
    }

    function backgroundName(uint8 v) internal pure returns (string memory) {
        if (v == 0) return "Bone White";
        if (v == 1) return "Ash Grey";
        if (v == 2) return "Charcoal";
        if (v == 3) return "River Fog";
        if (v == 4) return "Ember Orange";
        if (v == 5) return "Gilded Fog";
        return "Unknown";
    }

    function postureName(uint8 v) internal pure returns (string memory) {
        if (v == 0) return "Standing";
        if (v == 1) return "Arms Out";
        if (v == 2) return "Bowing";
        if (v == 3) return "Ascending";
        return "Unknown";
    }

    function cloakName(uint8 v) internal pure returns (string memory) {
        if (v == 0) return "Plain";
        if (v == 1) return "Hatched";
        if (v == 2) return "Tattered";
        if (v == 3) return "Embered";
        if (v == 4) return "Ash Flow";
        return "Unknown";
    }
}
