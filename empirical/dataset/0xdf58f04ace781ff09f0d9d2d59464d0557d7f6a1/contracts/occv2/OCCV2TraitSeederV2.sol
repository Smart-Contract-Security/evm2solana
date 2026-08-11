// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IOCCV2TraitRegistry} from "./interfaces/IOCCV2TraitRegistry.sol";
import {IOCCV2TraitSeeder} from "./interfaces/IOCCV2TraitSeeder.sol";
import {
    TraitCategory,
    TraitVariant,
    TraitSelection,
    CitizenTraits,
    FrozenIndices,
    MintRoll,
    NUM_CATEGORIES,
    NUM_MOODS
} from "./OCCV2TraitTypes.sol";

/// @title OCCV2TraitSeederV2 — drop-in replacement for the deployed
///        OCCV2TraitSeeder with a display-time Accessory eyes-mismatch guard.
///
/// @notice **Bug fixed (only behavioral difference vs v1).**
///         The v1 seeder applies an Accessory variant's `eyesBlockMask` at
///         selection time against the **at-mint** eyes index — to keep the
///         static Accessory deterministic across transfers. Correct for
///         long-term stability, but it leaves a visual gap: after a transfer
///         the displayed Eyes can reshuffle to an index that the variant's
///         mask was designed to exclude (e.g. the laser landing on a Citizen
///         whose currently-displayed eyes are wink/squinting/happy). The
///         laser then renders on top of closed eyes — a real visual bug.
///
///         This v2 adds a **post-selection display-time guard** to
///         `getTraitsForDisplay` only:
///           after the Accessory pick is computed (using the same at-mint
///           eyes context as v1, so totalWeight and the modulo math are
///           **identical**), it re-checks the picked variant's
///           `eyesBlockMask` against the **currently-displayed** eyes
///           index. If the displayed eyes are blocked, the Accessory is
///           substituted with idx 0 (the "none" Accessory variant — the
///           upload script sorts a `none.svg` to idx 0 for every category
///           that has one). When the eyes later reshuffle back to a
///           compatible type, the original Accessory returns automatically.
///
///         **Surgical by design.** Because the selection math is unchanged,
///         a Citizen whose Accessory pick wasn't laser (or any variant with a
///         non-zero `eyesBlockMask`) is *never* affected — same Accessory,
///         same metadata. Only Citizens whose at-mint Accessory pick has a
///         display-time eyes conflict are patched.
///
///         The mint-time entry point (`getMintRollTraits`) is **byte-for-byte
///         identical to v1** — only `getTraitsForDisplay` carries the new
///         guard. No effect on mint behaviour, rare-freeze decisions, or
///         storage layout.
///
/// @dev Drop-in replacement: same `IOCCV2TraitSeeder` interface, same
///      constructor shape. Swap on `OnChainCitizensV2` via
///      `setTraitSeeder(newAddress)`. The Accessory category's substitute
///      index is hard-coded as 0 to match the upload script's `none.*`
///      sort-first invariant.
contract OCCV2TraitSeederV2 is IOCCV2TraitSeeder {
    using TraitSelection for uint256;

    error OCCV2_ZeroAddress();

    IOCCV2TraitRegistry public immutable traitRegistry;

    /// @dev All-moods-allowed bitmask (six bits set).
    uint8 private constant ALL_MOODS_MASK = uint8((1 << NUM_MOODS) - 1);

    /// @dev Substitute Accessory index used by the display-time guard when
    ///      the picked variant's `eyesBlockMask` excludes the currently-
    ///      displayed eyes. The upload script (`scripts/occv2/upload-traits.ts`)
    ///      sorts `none.svg` to idx 0 for every category that has one — see
    ///      its `readTraitDir` sort rule. The Accessory category does have a
    ///      `none.svg`, so idx 0 is the empty/no-accessory variant.
    uint16 private constant ACCESSORY_NONE_IDX = 0;

    struct FilterContext {
        bool isMale;
        uint8 moodBit;
        uint16 hairIdx;
        uint16 eyesIdx;    // at-mint eyes index (for accessory eyesBlockMask only)
        bool hairResolved;
        bool eyesResolved;
    }

    constructor(address _traitRegistry) {
        if (_traitRegistry == address(0)) revert OCCV2_ZeroAddress();
        traitRegistry = IOCCV2TraitRegistry(_traitRegistry);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Entry points
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IOCCV2TraitSeeder
    /// @dev Unchanged from v1 — verbatim. Mint-time roll only walks the 6
    ///      categories that affect the freeze decision. Does not run the
    ///      display-time Accessory guard (mint never deals with reshuffled
    ///      display eyes).
    function getMintRollTraits(uint256 permSeed, uint256 reshSeedAtMint)
        external
        view
        returns (MintRoll memory roll)
    {
        bool isMale = (permSeed % 2) == 0;
        uint8 moodIdx = uint8(
            uint256(keccak256(abi.encodePacked(reshSeedAtMint, "mood"))) % NUM_MOODS
        );
        uint8 moodBit = uint8(1 << moodIdx);

        FilterContext memory ctx;
        ctx.isMale = isMale;

        (roll.eyesIdx, roll.eyesWeight) =
            _rollCategoryAtMint(TraitCategory.Eyes, reshSeedAtMint, ctx, moodBit);
        (roll.eyebrowsIdx, roll.eyebrowsWeight) =
            _rollCategoryAtMint(TraitCategory.Eyebrows, reshSeedAtMint, ctx, moodBit);
        (roll.mouthIdx, roll.mouthWeight) =
            _rollCategoryAtMint(TraitCategory.Mouth, reshSeedAtMint, ctx, moodBit);

        (uint16 hairIdx, ) =
            _rollCategoryAtMint(TraitCategory.Hair, permSeed, ctx, 0);
        ctx.hairIdx = hairIdx;
        ctx.hairResolved = true;

        (roll.clothingIdx, roll.clothingWeight) =
            _rollCategoryAtMint(TraitCategory.Clothing, reshSeedAtMint, ctx, 0);
        (roll.accessoryIIIdx, roll.accessoryIIWeight) =
            _rollCategoryAtMint(TraitCategory.AccessoryII, reshSeedAtMint, ctx, 0);
    }

    function _rollCategoryAtMint(
        TraitCategory category,
        uint256 categorySeed,
        FilterContext memory ctx,
        uint8 moodBit
    ) internal view returns (uint16 idx, uint16 weight) {
        uint256 count = traitRegistry.getTraitCount(category);
        if (count == 0) return (0, 0);
        uint256 subSeed = uint256(keccak256(abi.encodePacked(
            categorySeed, uint8(uint256(category))
        )));
        ctx.moodBit = moodBit;
        return _selectVariant(
            category, count, subSeed, ctx, moodBit,
            /* excludeRares = */ false,
            /* threshold    = */ 0
        );
    }

    /// @inheritdoc IOCCV2TraitSeeder
    /// @dev v2 difference: a post-selection display-eyes guard on the
    ///      Accessory category only. See the contract-level NatSpec.
    function getTraitsForDisplay(
        uint256 permSeed,
        uint256 reshSeed,
        uint256 reshSeedAtMint,
        FrozenIndices memory frozen,
        uint16 eyesThreshold,
        uint16 eyebrowsThreshold,
        uint16 mouthThreshold,
        uint16 clothingThreshold,
        uint16 accessoryIIThreshold
    ) external view returns (CitizenTraits memory traits) {
        bool isMale = (permSeed % 2) == 0;
        traits.isMale = isMale;

        uint8 displayMoodIdx = _pickConstrainedMood(reshSeed, frozen, isMale);
        traits.appliedMoodIndex = displayMoodIdx;
        uint8 displayMoodBit = uint8(1 << displayMoodIdx);

        uint16 atMintEyesIdx = _deriveAtMintEyes(permSeed, reshSeedAtMint, frozen.eyes, isMale);

        FilterContext memory ctx;
        ctx.isMale = isMale;

        for (uint256 i = 0; i < NUM_CATEGORIES; i++) {
            TraitCategory category = TraitCategory(i);

            if (category == TraitCategory.HairBack) {
                traits.traitIndices[i] = traits.traitIndices[uint256(TraitCategory.Hair)];
                continue;
            }

            uint256 count = traitRegistry.getTraitCount(category);
            if (count == 0) {
                traits.traitIndices[i] = 0;
                continue;
            }

            uint16 picked;
            if (_isReshufflable(category)) {
                uint16 frozenIdx = _frozenIdxFor(category, frozen);
                if (frozenIdx > 0) {
                    picked = frozenIdx;
                } else {
                    uint16 threshold = _thresholdFor(
                        category,
                        eyesThreshold,
                        eyebrowsThreshold,
                        mouthThreshold,
                        clothingThreshold,
                        accessoryIIThreshold
                    );
                    uint8 catMoodBit = _isExpressionCategory(category) ? displayMoodBit : 0;
                    ctx.moodBit = catMoodBit;
                    uint256 subSeed = uint256(keccak256(abi.encodePacked(reshSeed, uint8(i))));
                    (picked, ) = _selectVariant(
                        category,
                        count,
                        subSeed,
                        ctx,
                        catMoodBit,
                        /* excludeRares = */ true,
                        threshold
                    );
                }
            } else {
                // Static category — deterministic from permSeed + AT-MINT eyes context.
                uint256 subSeed = uint256(keccak256(abi.encodePacked(permSeed, uint8(i))));
                ctx.moodBit = 0;
                (picked, ) = _selectVariant(
                    category,
                    count,
                    subSeed,
                    ctx,
                    0,
                    /* excludeRares = */ false,
                    /* threshold    = */ 0
                );
            }

            // ── v2 BUG FIX ──────────────────────────────────────────────────
            // Display-time Accessory guard. Applied AFTER the v1 selection
            // (totalWeight + modulo) has already run with at-mint eyes
            // context, so this never changes the selection for any Citizen
            // whose Accessory pick doesn't have an eyes-mismatch right now.
            //
            // Citizens with `picked == 0` already have no Accessory; nothing
            // to substitute. Citizens whose `picked` variant has a zero
            // `eyesBlockMask` (i.e. no eye restrictions) are also untouched.
            // Only when (picked != 0) AND (picked.eyesBlockMask blocks the
            // currently-displayed eyes) do we substitute idx 0 ("none").
            if (
                category == TraitCategory.Accessory &&
                picked != ACCESSORY_NONE_IDX
            ) {
                uint32 eyesBlock = traitRegistry
                    .getTraitVariant(TraitCategory.Accessory, picked)
                    .eyesBlockMask;
                if (eyesBlock != 0) {
                    uint16 displayEyesIdx = traits
                        .traitIndices[uint256(TraitCategory.Eyes)];
                    if (
                        (eyesBlock &
                            (uint32(1) << uint32(displayEyesIdx))) != 0
                    ) {
                        picked = ACCESSORY_NONE_IDX;
                    }
                }
            }
            // ────────────────────────────────────────────────────────────────

            traits.traitIndices[i] = picked;

            // Update context. For Eyes, the AT-MINT eyes index drives
            // Accessory selection (preserves v1's "Accessory is determined
            // by mint state" invariant) — the display-eyes guard above is
            // the only place the *currently-displayed* eyes feeds back in.
            if (category == TraitCategory.Eyes) {
                ctx.eyesIdx = atMintEyesIdx;
                ctx.eyesResolved = true;
            } else if (category == TraitCategory.Hair) {
                ctx.hairIdx = picked;
                ctx.hairResolved = true;
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internals — all verbatim copies from v1.
    // ─────────────────────────────────────────────────────────────────────────

    function _pickConstrainedMood(
        uint256 reshSeed,
        FrozenIndices memory frozen,
        bool isMale
    ) internal view returns (uint8) {
        uint8 mask = ALL_MOODS_MASK;

        if (frozen.eyes > 0) {
            uint8 mg = traitRegistry.getTraitVariant(TraitCategory.Eyes, frozen.eyes).moodGroups;
            if (mg != 0) mask &= mg;
        }
        if (frozen.eyebrows > 0) {
            uint8 mg = traitRegistry.getTraitVariant(TraitCategory.Eyebrows, frozen.eyebrows).moodGroups;
            if (mg != 0) mask &= mg;
        }
        if (frozen.mouth > 0) {
            uint8 mg = traitRegistry.getTraitVariant(TraitCategory.Mouth, frozen.mouth).moodGroups;
            if (mg != 0) mask &= mg;
        }

        if (mask == 0) {
            mask = ALL_MOODS_MASK;
        }

        uint256 setCount = 0;
        for (uint256 b = 0; b < NUM_MOODS; b++) {
            if ((mask & (uint8(1) << uint8(b))) != 0) setCount++;
        }

        uint256 pick = uint256(keccak256(abi.encodePacked(reshSeed, "mood"))) % setCount;
        uint256 j = 0;
        for (uint256 b = 0; b < NUM_MOODS; b++) {
            if ((mask & (uint8(1) << uint8(b))) != 0) {
                if (j == pick) {
                    isMale; // silence unused-var warning
                    return uint8(b);
                }
                j++;
            }
        }
        return 0;
    }

    function _deriveAtMintEyes(
        uint256 /* permSeed */,
        uint256 reshSeedAtMint,
        uint16 frozenEyes,
        bool isMale
    ) internal view returns (uint16) {
        if (frozenEyes > 0) return frozenEyes;

        uint256 count = traitRegistry.getTraitCount(TraitCategory.Eyes);
        if (count == 0) return 0;

        uint8 moodIdx = uint8(
            uint256(keccak256(abi.encodePacked(reshSeedAtMint, "mood"))) % NUM_MOODS
        );
        uint8 moodBit = uint8(1 << moodIdx);

        FilterContext memory ctx;
        ctx.isMale = isMale;

        uint256 subSeed = uint256(keccak256(abi.encodePacked(
            reshSeedAtMint, uint8(uint256(TraitCategory.Eyes))
        )));

        (uint16 eyesIdx, ) = _selectVariant(
            TraitCategory.Eyes,
            count,
            subSeed,
            ctx,
            moodBit,
            /* excludeRares = */ false,
            /* threshold    = */ 0
        );
        return eyesIdx;
    }

    function _selectVariant(
        TraitCategory category,
        uint256 count,
        uint256 subSeed,
        FilterContext memory ctx,
        uint8 moodBit,
        bool excludeRares,
        uint16 threshold
    ) internal view returns (uint16 idx, uint16 weight) {
        uint256[] memory words = traitRegistry.getSelectionData(category);

        uint256 totalWeight = 0;
        for (uint256 i = 0; i < count; i++) {
            uint256 word = words[i];
            if (_isCompatible(word, category, ctx, moodBit)) {
                uint16 w = word.weight();
                if (excludeRares && w < threshold) continue;
                totalWeight += w;
            }
        }

        if (totalWeight == 0) return (0, 0);

        uint256 roll = subSeed % totalWeight;

        uint256 cumulative = 0;
        for (uint256 i = 0; i < count; i++) {
            uint256 word = words[i];
            if (!_isCompatible(word, category, ctx, moodBit)) continue;
            uint16 w = word.weight();
            if (excludeRares && w < threshold) continue;
            cumulative += w;
            if (roll < cumulative) return (uint16(i), w);
        }
        return (0, 0);
    }

    function _isCompatible(
        uint256 word,
        TraitCategory category,
        FilterContext memory ctx,
        uint8 moodBit
    ) internal pure returns (bool) {
        if (ctx.isMale && word.femaleOnly()) return false;
        if (!ctx.isMale && word.maleOnly()) return false;

        if (moodBit != 0) {
            uint8 mg = word.moodGroups();
            if (mg != 0 && (mg & moodBit) == 0) return false;
        }

        if (category == TraitCategory.Accessory) {
            uint32 reqHair = word.requiredHairMask();
            if (reqHair != 0) {
                if (!ctx.hairResolved) return false;
                if ((reqHair & (uint32(1) << uint32(ctx.hairIdx))) == 0) return false;
            }
            uint32 eyesBlock = word.eyesBlockMask();
            if (eyesBlock != 0 && ctx.eyesResolved) {
                if ((eyesBlock & (uint32(1) << uint32(ctx.eyesIdx))) != 0) return false;
            }
        }

        if (category == TraitCategory.AccessoryII) {
            uint32 inc = word.incompatFlags();
            if (inc != 0 && ctx.hairResolved) {
                if ((inc & (uint32(1) << uint32(ctx.hairIdx))) != 0) return false;
            }
        }

        return true;
    }

    function _isReshufflable(TraitCategory category) internal pure returns (bool) {
        return category == TraitCategory.Eyes ||
               category == TraitCategory.Eyebrows ||
               category == TraitCategory.Mouth ||
               category == TraitCategory.Clothing ||
               category == TraitCategory.AccessoryII;
    }

    function _isExpressionCategory(TraitCategory category) internal pure returns (bool) {
        return category == TraitCategory.Eyes ||
               category == TraitCategory.Eyebrows ||
               category == TraitCategory.Mouth;
    }

    function _frozenIdxFor(TraitCategory category, FrozenIndices memory frozen) internal pure returns (uint16) {
        if (category == TraitCategory.Eyes) return frozen.eyes;
        if (category == TraitCategory.Eyebrows) return frozen.eyebrows;
        if (category == TraitCategory.Mouth) return frozen.mouth;
        if (category == TraitCategory.Clothing) return frozen.clothing;
        if (category == TraitCategory.AccessoryII) return frozen.accessoryII;
        return 0;
    }

    function _thresholdFor(
        TraitCategory category,
        uint16 eyesThreshold,
        uint16 eyebrowsThreshold,
        uint16 mouthThreshold,
        uint16 clothingThreshold,
        uint16 accessoryIIThreshold
    ) internal pure returns (uint16) {
        if (category == TraitCategory.Eyes) return eyesThreshold;
        if (category == TraitCategory.Eyebrows) return eyebrowsThreshold;
        if (category == TraitCategory.Mouth) return mouthThreshold;
        if (category == TraitCategory.Clothing) return clothingThreshold;
        return accessoryIIThreshold;
    }
}
