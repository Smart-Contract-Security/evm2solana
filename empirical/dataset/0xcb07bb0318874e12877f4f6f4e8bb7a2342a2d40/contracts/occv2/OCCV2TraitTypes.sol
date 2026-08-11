// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title OCCV2TraitTypes — Enums, structs, and constants for the OCC V2 trait system
/// @notice Mirrors the MEGANS trait-types layout, with three OCC V2-specific additions:
///           1. `FrozenIndices` — the four reshufflable-category freeze slots tracked
///              on the NFT per token.
///           2. `appliedMoodIndex` — extended into `CitizenTraits` per R27 option (a)
///              so the MetadataGenerator can emit the Mood attribute without
///              re-deriving it (single source of truth for the seeder's applied mood).
///           3. `TokenState` — the per-token storage struct that fits into one slot.

/// @notice Categories of visual traits that compose a Citizen's appearance
enum TraitCategory {
    Background,   // 0  — Solid color rectangle or simple pattern
    Body,         // 1  — Torso/shoulders silhouette
    SkinTone,     // 2  — Color index (not SVG path data)
    HeadShape,    // 3  — Head outline
    Eyes,         // 4  — Eye shapes and pupils                  [RESHUFFLABLE]
    Eyebrows,     // 5  — Eyebrow shapes                         [RESHUFFLABLE]
    Mouth,        // 6  — Mouth/lips                             [RESHUFFLABLE]
    Hair,         // 7  — Hairstyles (front strands, bangs)
    FacialHair,   // 8  — Beards/mustaches (male-specific)
    Clothing,     // 9  — Shirt/jacket/dress                     [RESHUFFLABLE]
    Accessory,    // 10 — Hats, glasses, earrings
    Special,      // 11 — Ultra-rare overlays
    HairBack,     // 12 — Hair back-fill (auto-paired with Hair)
    AccessoryII   // 13 — Head-worn accessories                  [RESHUFFLABLE]
}

/// @dev Mood groups for expression coherence (bitmask flags).
///      A trait with moodGroups == 0 is universal (compatible with all moods).
uint256 constant NUM_MOODS = 6;

/// @notice A single variant within a trait category. Identical shape to MEGANS.
struct TraitVariant {
    string name;              // Human-readable name
    address svgDataPointer;   // SSTORE2 pointer to SVG bytes
    uint16 weight;            // Rarity weight (higher = more common)
    bool maleOnly;            // Only available for male characters
    bool femaleOnly;          // Only available for female characters
    uint8 moodGroups;         // Bitmask of compatible moods (0 = all moods)
    uint16 allowedColorMask;  // Bitmask of allowed clothing color indices (0 = all colors)
    uint32 incompatFlags;     // Hair-index bitmask; AccessoryII variants block these hairs
    uint32 requiredHairMask;  // Hair-index bitmask; Accessory variants only roll for these hairs
    uint32 eyesBlockMask;     // Eyes-index bitmask; Accessory variants are excluded for these eyes
}

/// @notice Full set of resolved trait indices for a Citizen.
/// @dev OCC V2 extends the MEGANS shape with `appliedMoodIndex` per R27.
///      The seeder writes the actually-applied mood here (single source of truth)
///      so the MetadataGenerator can emit the Mood attribute without re-deriving it.
struct CitizenTraits {
    uint16[14] traitIndices;  // One index per TraitCategory
    bool isMale;              // Gender derived from the PERMANENT seed (locked)
    uint8 appliedMoodIndex;   // 0..5, matches _moodName table (R27)
}

/// @notice Per-token freeze state for the five reshufflable categories. A
///         non-zero value means "this slot rolled a rare at mint and is frozen
///         to that variant forever." Zero means "fluid — reshuffle on transfer."
///         The constraint that idx 0 must be non-rare per category (enforced
///         by the upload script) keeps the zero sentinel from colliding with a
///         legitimate freeze.
struct FrozenIndices {
    uint16 eyes;
    uint16 eyebrows;
    uint16 mouth;
    uint16 clothing;
    uint16 accessoryII;
}

/// @notice Mint-time roll result for the 5 reshufflable categories — returned
///         by `OCCV2TraitSeeder.getMintRollTraits`. Includes the variant index
///         AND the variant weight for each reshufflable slot, so the calling
///         NFT contract can run its `_maybeFreezeRareCached` decision purely
///         from this struct without a second registry read per category.
///         Hair is NOT included even though it's rolled internally (purely as
///         filter context for AccessoryII's `incompatFlags` check); the NFT
///         doesn't need it.
struct MintRoll {
    uint16 eyesIdx;
    uint16 eyesWeight;
    uint16 eyebrowsIdx;
    uint16 eyebrowsWeight;
    uint16 mouthIdx;
    uint16 mouthWeight;
    uint16 clothingIdx;
    uint16 clothingWeight;
    uint16 accessoryIIIdx;
    uint16 accessoryIIWeight;
}

/// @notice Per-token state stored on the NFT contract. Packs into a single 32-byte slot.
struct TokenState {
    uint64 mintBlock;                 // 8 bytes
    uint32 transferCount;             // 4 bytes
    uint16 frozenEyesIdx;             // 2 bytes
    uint16 frozenEyebrowsIdx;         // 2 bytes
    uint16 frozenMouthIdx;            // 2 bytes
    uint16 frozenClothingIdx;         // 2 bytes
    uint16 frozenAccessoryIIIdx;      // 2 bytes — AccessoryII is reshufflable too
    // ── Owner-mutable extensions ────────────────────────────────────────────
    bool traitsLocked;                // 1 byte — owner-set freeze flag
    uint32 lockedAtTransferCount;     // 4 bytes — snapshot of transferCount at freeze time
    bool backgroundReshuffleEnabled;  // 1 byte — flipped true on first rerollBackground
    uint32 backgroundRerollNonce;     // 4 bytes — feeds bg color derivation
    // Total: 32 bytes — fills one 32-byte slot exactly.
}

/// @dev Total number of trait categories
uint256 constant NUM_CATEGORIES = 14;

/// @title TraitSelection — bit-packed selection data for one trait variant
/// @notice The trait seeder's weighted pick only needs 7 of `TraitVariant`'s
///         fields (weight, the two gender flags, moodGroups, and the three
///         filter masks). It never needs `name` or `svgDataPointer`. This
///         library packs those 7 fields into a single 32-byte word so the
///         registry can hand the seeder one word per variant — fetched for a
///         whole category in ONE batched call — instead of the seeder making
///         one external call per variant and ABI-decoding the unused `name`
///         string each time. This is the core of the OCC V2 mint-gas
///         optimization (registry read-path: ~1 call + ~1 SLOAD per variant,
///         down from ~1 call + ~3 SLOADs + a string decode per variant).
/// @dev Layout (least-significant bit first):
///        bits   0– 15  weight            (uint16)
///        bit       16  maleOnly
///        bit       17  femaleOnly
///        bits  18– 25  moodGroups        (uint8)
///        bits  26– 57  incompatFlags     (uint32)
///        bits  58– 89  requiredHairMask  (uint32)
///        bits  90–121  eyesBlockMask     (uint32)
///      Top 134 bits are unused. `allowedColorMask` is intentionally NOT
///      packed — only the MetadataGenerator needs it, and it reads the full
///      `TraitVariant` anyway for the variant `name`.
library TraitSelection {
    function pack(
        uint16 weight_,
        bool maleOnly_,
        bool femaleOnly_,
        uint8 moodGroups_,
        uint32 incompatFlags_,
        uint32 requiredHairMask_,
        uint32 eyesBlockMask_
    ) internal pure returns (uint256 word) {
        word =
            uint256(weight_) |
            (uint256(moodGroups_) << 18) |
            (uint256(incompatFlags_) << 26) |
            (uint256(requiredHairMask_) << 58) |
            (uint256(eyesBlockMask_) << 90);
        if (maleOnly_) word |= (uint256(1) << 16);
        if (femaleOnly_) word |= (uint256(1) << 17);
    }

    function weight(uint256 word) internal pure returns (uint16) {
        return uint16(word);
    }

    function maleOnly(uint256 word) internal pure returns (bool) {
        return ((word >> 16) & 1) == 1;
    }

    function femaleOnly(uint256 word) internal pure returns (bool) {
        return ((word >> 17) & 1) == 1;
    }

    function moodGroups(uint256 word) internal pure returns (uint8) {
        return uint8(word >> 18);
    }

    function incompatFlags(uint256 word) internal pure returns (uint32) {
        return uint32(word >> 26);
    }

    function requiredHairMask(uint256 word) internal pure returns (uint32) {
        return uint32(word >> 58);
    }

    function eyesBlockMask(uint256 word) internal pure returns (uint32) {
        return uint32(word >> 90);
    }
}
