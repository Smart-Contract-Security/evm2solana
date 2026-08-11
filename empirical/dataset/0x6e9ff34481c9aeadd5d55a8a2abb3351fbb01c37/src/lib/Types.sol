// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Types — shared constants, enums, structs for Obol & Ash
/// @notice All numeric ceilings, tier IDs, and packed-trait helpers live here.
library Types {
    // --- Supply / mint caps ---
    uint256 internal constant TOTAL_SUPPLY = 10_000;
    uint8   internal constant MAX_QTY_PER_TX = 10;   // souls per summon
    uint8   internal constant MAX_TX_PER_WALLET = 10;

    // --- Royalty ---
    uint16  internal constant ROYALTY_BPS = 1000; // 10%

    // --- Default mint price (USD basis points; 10000 bps = $1.00). Owner-adjustable post-deploy. ---
    uint16  internal constant PRICE_BPS = 2000;   // $0.20 per soul
    uint16  internal constant FREE_FLOOR_BPS = 1000; // $0.10 floor used for free-soul Drown payouts

    // --- Mythic cap ---
    uint16  internal constant MYTHIC_CAP = 10;

    // --- Tier IDs ---
    uint8 internal constant TIER_COMMON     = 0; // Wisp
    uint8 internal constant TIER_UNCOMMON   = 1; // Coinbearer
    uint8 internal constant TIER_RARE       = 2; // Skiffsoul
    uint8 internal constant TIER_EPIC       = 3; // Lanternward
    uint8 internal constant TIER_LEGENDARY  = 4; // Ember-Drowned
    uint8 internal constant TIER_MYTHIC     = 5; // Riverborn

    // --- Mint drop weights (out of 10000) ---
    uint16 internal constant DROP_COMMON     = 6000;
    uint16 internal constant DROP_UNCOMMON   = 2500;
    uint16 internal constant DROP_RARE       = 1000;
    uint16 internal constant DROP_EPIC       = 400;
    uint16 internal constant DROP_LEGENDARY  = 90;
    uint16 internal constant DROP_MYTHIC     = 10;

    // --- Crossing break probabilities (out of 10000) ---
    uint16 internal constant BREAK_BPS_T0 = 300;   // 3%
    uint16 internal constant BREAK_BPS_T1 = 500;   // 5%
    uint16 internal constant BREAK_BPS_T2 = 800;   // 8%
    uint16 internal constant BREAK_BPS_T3 = 1500;  // 15%
    uint16 internal constant BREAK_BPS_T4 = 5000;  // 50%

    // --- Payout multiplier weights (out of 10000) ---
    uint16 internal constant PAYOUT_1X_THRESHOLD = 7000; // <7000 -> 1x
    uint16 internal constant PAYOUT_2X_THRESHOLD = 9500; // <9500 -> 2x, else 3x

    // --- Trait slots ---
    uint8 internal constant SLOT_HOOD_SHAPE   = 0;
    uint8 internal constant SLOT_FACE_INSIDE  = 1;
    uint8 internal constant SLOT_OBOL_POS     = 2;
    uint8 internal constant SLOT_COIN_MARK    = 3;
    uint8 internal constant SLOT_TOP_SIGIL    = 4;
    uint8 internal constant SLOT_BACKGROUND   = 5;
    uint8 internal constant SLOT_POSTURE      = 6;
    uint8 internal constant SLOT_CLOAK_DETAIL = 7;

    /// @notice Token packed into a single uint256.
    /// Layout (LSB first):
    ///   bits 0-2   (3)  tier
    ///   bits 3-10  (8)  hoodShape
    ///   bits 11-18 (8)  faceInside
    ///   bits 19-26 (8)  obolPosition
    ///   bits 27-34 (8)  coinMark
    ///   bits 35-42 (8)  topSigil
    ///   bits 43-50 (8)  background
    ///   bits 51-58 (8)  posture
    ///   bits 59-66 (8)  cloakDetail
    ///   bits 67-82 (16) mintPriceSnapshotBps (USD bps; internal, not in metadata)
    ///   bits 83-86 (4)  ascensionCount
    ///   bits 87-255     reserved
    struct TokenData {
        uint8  tier;
        uint8  hoodShape;
        uint8  faceInside;
        uint8  obolPosition;
        uint8  coinMark;
        uint8  topSigil;
        uint8  background;
        uint8  posture;
        uint8  cloakDetail;
        uint16 mintPriceSnapshotBps;
        uint8  ascensionCount;
    }

    function pack(TokenData memory d) internal pure returns (uint256 packed) {
        packed = uint256(d.tier) & 0x7;
        packed |= uint256(d.hoodShape)    << 3;
        packed |= uint256(d.faceInside)   << 11;
        packed |= uint256(d.obolPosition) << 19;
        packed |= uint256(d.coinMark)     << 27;
        packed |= uint256(d.topSigil)     << 35;
        packed |= uint256(d.background)   << 43;
        packed |= uint256(d.posture)      << 51;
        packed |= uint256(d.cloakDetail)  << 59;
        packed |= uint256(d.mintPriceSnapshotBps) << 67;
        packed |= uint256(d.ascensionCount & 0xF) << 83;
    }

    function unpack(uint256 packed) internal pure returns (TokenData memory d) {
        d.tier                 = uint8(packed        & 0x7);
        d.hoodShape            = uint8((packed >> 3)  & 0xFF);
        d.faceInside           = uint8((packed >> 11) & 0xFF);
        d.obolPosition         = uint8((packed >> 19) & 0xFF);
        d.coinMark             = uint8((packed >> 27) & 0xFF);
        d.topSigil             = uint8((packed >> 35) & 0xFF);
        d.background           = uint8((packed >> 43) & 0xFF);
        d.posture              = uint8((packed >> 51) & 0xFF);
        d.cloakDetail          = uint8((packed >> 59) & 0xFF);
        d.mintPriceSnapshotBps = uint16((packed >> 67) & 0xFFFF);
        d.ascensionCount       = uint8((packed >> 83)  & 0xF);
    }

    function tierName(uint8 tier) internal pure returns (string memory) {
        if (tier == TIER_COMMON)    return "Wisp";
        if (tier == TIER_UNCOMMON)  return "Coinbearer";
        if (tier == TIER_RARE)      return "Skiffsoul";
        if (tier == TIER_EPIC)      return "Lanternward";
        if (tier == TIER_LEGENDARY) return "Ember-Drowned";
        if (tier == TIER_MYTHIC)    return "Riverborn";
        return "Unknown";
    }

    function tierRarity(uint8 tier) internal pure returns (string memory) {
        if (tier == TIER_COMMON)    return "Common";
        if (tier == TIER_UNCOMMON)  return "Uncommon";
        if (tier == TIER_RARE)      return "Rare";
        if (tier == TIER_EPIC)      return "Epic";
        if (tier == TIER_LEGENDARY) return "Legendary";
        if (tier == TIER_MYTHIC)    return "Mythic";
        return "Unknown";
    }
}
