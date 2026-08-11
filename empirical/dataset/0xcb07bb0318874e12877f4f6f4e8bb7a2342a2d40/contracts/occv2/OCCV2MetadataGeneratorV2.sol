// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IOCCV2MetadataGenerator} from "./interfaces/IOCCV2MetadataGenerator.sol";
import {IOCCV2SVGRenderer} from "./interfaces/IOCCV2SVGRenderer.sol";
import {IOCCV2TraitRegistry} from "./interfaces/IOCCV2TraitRegistry.sol";
import {IOCCV2TraitSeeder} from "./interfaces/IOCCV2TraitSeeder.sol";
import {
    TraitCategory,
    TraitVariant,
    CitizenTraits,
    FrozenIndices,
    NUM_CATEGORIES,
    NUM_MOODS
} from "./OCCV2TraitTypes.sol";
import {Base64} from "solady/src/utils/Base64.sol";
import {LibString} from "solady/src/utils/LibString.sol";

/// @title OCCV2MetadataGeneratorV2 — drop-in replacement for the deployed
///        OCCV2MetadataGenerator that fixes the phantom "Hair Color" attribute
///        bug for hairless Citizens.
///
/// @notice **Bug fixed (only behavioral difference vs v1).**
///         The deployed v1 metadata generator emits a `Hair Color` attribute on
///         every Citizen, regardless of whether any hair-bearing trait is
///         actually visible on the rendered art. For a male Citizen that minted
///         with `Hair = male-bald` *and* `Facial Hair = clean-shaven`, the
///         attribute describes a color that exists nowhere on the art (no hair
///         path is drawn for either trait), which is misleading on
///         marketplaces and pollutes trait-rarity tooling.
///
///         This v2 emits the `Hair Color` attribute only when the Citizen has
///         at least one hair-bearing trait visible:
///           • female Citizens always have visible hair (the collection has no
///             bald female hair variant) → always emit `Hair Color`,
///           • male Citizens emit `Hair Color` iff Hair is not the bald/none
///             sentinel OR Facial Hair is not the clean-shaven/none sentinel.
///
///         Detection is **name-based** against the registry — robust to
///         variant index reordering. The recognised "empty" names are:
///           Hair         → "male-bald", "bald", "none"
///           Facial Hair  → "clean-shaven", "none"
///
/// @dev Drop-in replacement: same `IOCCV2MetadataGenerator` interface, same
///      constructor shape, identical output in all other respects. Swap on
///      `OnChainCitizensV2` via `setMetadataGenerator(newAddress)`. Nothing
///      else in the system changes.
contract OCCV2MetadataGeneratorV2 is IOCCV2MetadataGenerator {
    using LibString for uint256;

    error OCCV2_ZeroAddress();

    IOCCV2SVGRenderer public immutable svgRenderer;
    IOCCV2TraitRegistry public immutable traitRegistry;
    IOCCV2TraitSeeder public immutable traitSeeder;

    uint256 private constant NUM_SKIN_TONES = 7;
    uint256 private constant NUM_HAIR_COLORS = 10;
    uint256 private constant NUM_CLOTHING_COLORS = 11;
    uint256 private constant NUM_BG_COLORS = 9;

    /// @dev keccak256 hashes of the "empty" variant names. Cheap O(1)
    ///      comparisons against the variant `name` we read from the registry.
    bytes32 private constant _HASH_HAIR_MALE_BALD = keccak256(bytes("male-bald"));
    bytes32 private constant _HASH_HAIR_BALD = keccak256(bytes("bald"));
    bytes32 private constant _HASH_HAIR_NONE = keccak256(bytes("none"));
    bytes32 private constant _HASH_FACIAL_CLEAN_SHAVEN = keccak256(bytes("clean-shaven"));
    bytes32 private constant _HASH_FACIAL_NONE = keccak256(bytes("none"));

    constructor(
        address _traitRegistry,
        address _svgRenderer,
        address _traitSeeder
    ) {
        if (_traitRegistry == address(0) || _svgRenderer == address(0) || _traitSeeder == address(0)) {
            revert OCCV2_ZeroAddress();
        }
        traitRegistry = IOCCV2TraitRegistry(_traitRegistry);
        svgRenderer = IOCCV2SVGRenderer(_svgRenderer);
        traitSeeder = IOCCV2TraitSeeder(_traitSeeder);
    }

    /// @inheritdoc IOCCV2MetadataGenerator
    function generateMetadata(
        uint256 tokenId,
        uint256 permSeed,
        uint256 reshSeed,
        uint256 reshSeedAtMint,
        FrozenIndices calldata frozen,
        uint16 eyesThreshold,
        uint16 eyebrowsThreshold,
        uint16 mouthThreshold,
        uint16 clothingThreshold,
        uint16 accessoryIIThreshold,
        uint32 transferCount,
        bool traitsLocked,
        bool backgroundReshuffleEnabled,
        uint32 backgroundRerollNonce
    ) external view returns (string memory) {
        CitizenTraits memory traits = traitSeeder.getTraitsForDisplay(
            permSeed,
            reshSeed,
            reshSeedAtMint,
            frozen,
            eyesThreshold,
            eyebrowsThreshold,
            mouthThreshold,
            clothingThreshold,
            accessoryIIThreshold
        );

        uint256 skinIdx = _skinToneIndex(permSeed);
        uint256 hairIdx = _hairColorIndex(permSeed);
        bytes3 skinColor = _skinTone(skinIdx);
        bytes3 hairColor = _hairColor(hairIdx);

        uint16 clothingColorMask = 0;
        TraitCategory clothingCat = TraitCategory.Clothing;
        uint256 clothingCount = traitRegistry.getTraitCount(clothingCat);
        uint16 clothingIdx = traits.traitIndices[uint256(clothingCat)];
        if (clothingCount > 0 && clothingIdx < clothingCount) {
            TraitVariant memory clothingVariant = traitRegistry.getTraitVariant(clothingCat, clothingIdx);
            clothingColorMask = clothingVariant.allowedColorMask;
        }
        bytes3 clothingColor = _deriveClothingColor(reshSeed, clothingColorMask);

        (uint8 bgIdx, bytes3 backgroundColor) = _deriveBackgroundColor(
            reshSeed,
            backgroundReshuffleEnabled,
            backgroundRerollNonce
        );

        string memory svg = svgRenderer.renderSVG(
            traits.traitIndices,
            traits.isMale,
            backgroundColor,
            skinColor,
            hairColor,
            clothingColor
        );

        string memory imageURI = string(
            bytes.concat(
                "data:image/svg+xml;base64,",
                bytes(Base64.encode(bytes(svg)))
            )
        );

        string memory attributes = _buildAttributes(
            traits,
            bgIdx,
            skinIdx,
            hairIdx,
            transferCount,
            traitsLocked
        );

        string memory json = string(
            bytes.concat(
                '{"name":"Citizen #',
                bytes(tokenId.toString()),
                '","description":"An OnChain Citizen. Fully on-chain SVG art; non-rare traits, if not locked, reshuffle on every wallet-to-wallet transfer while rare traits stay locked.","image":"',
                bytes(imageURI),
                '","attributes":[',
                bytes(attributes),
                "]}"
            )
        );

        return string(
            bytes.concat(
                "data:application/json;base64,",
                bytes(Base64.encode(bytes(json)))
            )
        );
    }

    function _buildAttributes(
        CitizenTraits memory traits,
        uint8 backgroundColorIndex,
        uint256 skinToneIndex,
        uint256 hairColorIndex,
        uint32 transferCount,
        bool traitsLocked
    ) internal view returns (string memory) {
        // Gender + Mood + Skin Tone — always emitted.
        bytes memory attrs = bytes.concat(
            '{"trait_type":"Gender","value":"',
            traits.isMale ? bytes("Male") : bytes("Female"),
            '"},',
            '{"trait_type":"Mood","value":"',
            bytes(_moodName(traits.appliedMoodIndex)),
            '"},',
            '{"trait_type":"Skin Tone","value":"',
            bytes(_skinToneName(skinToneIndex)),
            '"},'
        );

        // ── v2 BUG FIX ──────────────────────────────────────────────────────
        // Hair Color is emitted only when the Citizen has at least one
        // hair-bearing trait visible. Skipping the attribute entirely (rather
        // than emitting "Hair Color: None") keeps marketplace trait lists and
        // rarity tables clean.
        if (_hasVisibleHair(traits)) {
            attrs = bytes.concat(
                attrs,
                '{"trait_type":"Hair Color","value":"',
                bytes(_hairColorName(hairColorIndex)),
                '"},'
            );
        }
        // ────────────────────────────────────────────────────────────────────

        attrs = bytes.concat(
            attrs,
            '{"trait_type":"Background","value":"',
            bytes(_backgroundColorName(backgroundColorIndex)),
            '"},',
            '{"trait_type":"Transfer Count","value":',
            bytes(LibString.toString(uint256(transferCount))),
            ',"display_type":"number"},',
            '{"trait_type":"Traits Locked","value":"',
            traitsLocked ? bytes("Yes") : bytes("No"),
            '"}'
        );

        for (uint256 i = 0; i < NUM_CATEGORIES; i++) {
            TraitCategory category = TraitCategory(i);
            uint256 traitCount = traitRegistry.getTraitCount(category);

            if (traitCount == 0 || traits.traitIndices[i] >= traitCount) continue;

            if (i == 0) continue; // Background — emitted above from the derived color
            if (i == 1) continue; // Body — single variant per gender
            if (i == 3) continue; // HeadShape — single variant per gender
            if (i == 5) continue; // Eyebrows — mood-paired with Eyes
            if (i == 8 && !traits.isMale) continue; // FacialHair — male only
            if (i == 12) continue; // HairBack — auto-paired with Hair

            TraitVariant memory variant = traitRegistry.getTraitVariant(category, traits.traitIndices[i]);

            attrs = bytes.concat(
                attrs,
                ',{"trait_type":"',
                bytes(_categoryName(i)),
                '","value":"',
                bytes(variant.name),
                '"}'
            );
        }

        return string(attrs);
    }

    /// @dev Returns true if at least one hair-bearing trait is visible on
    ///      the rendered art. Female Citizens always return true (the
    ///      collection has no bald female hair variant). Male Citizens
    ///      return true if Hair is non-empty OR Facial Hair is non-empty.
    ///
    ///      The Hair and Facial Hair indices are bounds-checked; an
    ///      out-of-bounds index is treated as "no visible variant" for
    ///      that slot, matching the SVG renderer's behavior in
    ///      `_appendIfPresent` which skips rendering when the index is
    ///      past the registry's variant count.
    function _hasVisibleHair(CitizenTraits memory traits) internal view returns (bool) {
        if (!traits.isMale) return true;

        // Hair
        uint256 hairCount = traitRegistry.getTraitCount(TraitCategory.Hair);
        uint16 hairIdx = traits.traitIndices[uint256(TraitCategory.Hair)];
        if (hairCount > 0 && hairIdx < hairCount) {
            TraitVariant memory hair = traitRegistry.getTraitVariant(TraitCategory.Hair, hairIdx);
            if (!_isEmptyHairName(hair.name)) return true;
        }

        // Facial Hair
        uint256 facialCount = traitRegistry.getTraitCount(TraitCategory.FacialHair);
        uint16 facialIdx = traits.traitIndices[uint256(TraitCategory.FacialHair)];
        if (facialCount > 0 && facialIdx < facialCount) {
            TraitVariant memory facial = traitRegistry.getTraitVariant(TraitCategory.FacialHair, facialIdx);
            if (!_isEmptyFacialHairName(facial.name)) return true;
        }

        return false;
    }

    function _isEmptyHairName(string memory name) internal pure returns (bool) {
        bytes32 h = keccak256(bytes(name));
        return h == _HASH_HAIR_MALE_BALD || h == _HASH_HAIR_BALD || h == _HASH_HAIR_NONE;
    }

    function _isEmptyFacialHairName(string memory name) internal pure returns (bool) {
        bytes32 h = keccak256(bytes(name));
        return h == _HASH_FACIAL_CLEAN_SHAVEN || h == _HASH_FACIAL_NONE;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Color palettes + derivations — verbatim copies from v1. No behavior
    // change here; included so this contract is fully self-contained.
    // ─────────────────────────────────────────────────────────────────────────

    function _skinTone(uint256 index) internal pure returns (bytes3) {
        if (index == 0) return bytes3(0xFFE0BD);
        if (index == 1) return bytes3(0xFFDBB4);
        if (index == 2) return bytes3(0xF5D0A9);
        if (index == 3) return bytes3(0xEDB98A);
        if (index == 4) return bytes3(0xD08B5B);
        if (index == 5) return bytes3(0xAE5D29);
        return bytes3(0x7B5B44);
    }

    function _hairColor(uint256 index) internal pure returns (bytes3) {
        if (index == 0) return bytes3(0x090806);
        if (index == 1) return bytes3(0x2C222B);
        if (index == 2) return bytes3(0x71635A);
        if (index == 3) return bytes3(0xB7A69E);
        if (index == 4) return bytes3(0x8D4A43);
        if (index == 5) return bytes3(0xDEBC99);
        if (index == 6) return bytes3(0xD6C4C2);
        if (index == 7) return bytes3(0xECDCB0);
        return bytes3(0xE6E6E6);
    }

    function _clothingColor(uint256 index) internal pure returns (bytes3) {
        if (index == 0) return bytes3(0xE74C3C);
        if (index == 1) return bytes3(0x3498DB);
        if (index == 2) return bytes3(0x2ECC71);
        if (index == 3) return bytes3(0xE67E22);
        if (index == 4) return bytes3(0x9B59B6);
        if (index == 5) return bytes3(0xF1C40F);
        if (index == 6) return bytes3(0xE91E8F);
        if (index == 7) return bytes3(0x1ABC9C);
        if (index == 8) return bytes3(0xA0693E);
        if (index == 9) return bytes3(0xECF0F1);
        return bytes3(0x95A5A6);
    }

    function _backgroundColor(uint256 index) internal pure returns (bytes3) {
        if (index == 0) return bytes3(0xB5B5B5);
        if (index == 1) return bytes3(0xA8D5FF);
        if (index == 2) return bytes3(0xB8D8BA);
        if (index == 3) return bytes3(0xF2C4CE);
        if (index == 4) return bytes3(0xFD5D63);
        if (index == 5) return bytes3(0xFCBB59);
        if (index == 6) return bytes3(0xFFF2CC);
        if (index == 7) return bytes3(0x56483C);
        return bytes3(0xD4C4E8);
    }

    function _backgroundColorName(uint256 index) internal pure returns (string memory) {
        if (index == 0) return "Light Grey";
        if (index == 1) return "Sky Blue";
        if (index == 2) return "Sage";
        if (index == 3) return "Rose";
        if (index == 4) return "Light Red";
        if (index == 5) return "Light Orange";
        if (index == 6) return "Cream";
        if (index == 7) return "Ashen Brown";
        return "Lavender";
    }

    function _deriveBackgroundColor(
        uint256 reshSeed,
        bool reshuffleEnabled,
        uint32 rerollNonce
    ) internal pure returns (uint8 colorIndex, bytes3 colorRGB) {
        if (!reshuffleEnabled) {
            return (0, _backgroundColor(0));
        }
        uint256 seed = uint256(keccak256(abi.encodePacked(reshSeed, "bg", rerollNonce)));
        uint8 idx = uint8(seed % NUM_BG_COLORS);
        return (idx, _backgroundColor(idx));
    }

    function _categoryName(uint256 index) internal pure returns (string memory) {
        if (index == 0) return "Background";
        if (index == 1) return "Body";
        if (index == 2) return "Skin Tone";
        if (index == 3) return "Head Shape";
        if (index == 4) return "Eyes";
        if (index == 5) return "Eyebrows";
        if (index == 6) return "Mouth";
        if (index == 7) return "Hair";
        if (index == 8) return "Facial Hair";
        if (index == 9) return "Clothing";
        if (index == 10) return "Accessory";
        if (index == 11) return "Special";
        if (index == 12) return "Hair Back";
        return "Accessory II";
    }

    function _skinToneIndex(uint256 seed) internal pure returns (uint256) {
        uint256 subSeed = uint256(keccak256(abi.encodePacked(seed, uint8(2))));
        return subSeed % NUM_SKIN_TONES;
    }

    function _skinToneName(uint256 index) internal pure returns (string memory) {
        if (index == 0) return "Porcelain";
        if (index == 1) return "Ivory";
        if (index == 2) return "Beige";
        if (index == 3) return "Sand";
        if (index == 4) return "Caramel";
        if (index == 5) return "Toffee";
        return "Espresso";
    }

    function _moodName(uint256 index) internal pure returns (string memory) {
        if (index == 0) return "Happy";
        if (index == 1) return "Sad";
        if (index == 2) return "Surprised";
        if (index == 3) return "Bored";
        if (index == 4) return "Silly";
        return "Angry";
    }

    function _hairColorIndex(uint256 seed) internal pure returns (uint256) {
        uint256 subSeed = uint256(keccak256(abi.encodePacked(seed, "hair")));
        return subSeed % NUM_HAIR_COLORS;
    }

    function _hairColorName(uint256 index) internal pure returns (string memory) {
        if (index == 0) return "Black";
        if (index == 1) return "Dark Brown";
        if (index == 2) return "Brown";
        if (index == 3) return "Light Brown";
        if (index == 4) return "Auburn";
        if (index == 5) return "Strawberry";
        if (index == 6) return "Blonde";
        if (index == 7) return "Platinum";
        return "Grey";
    }

    function _deriveClothingColor(uint256 seed, uint16 allowedMask) internal pure returns (bytes3) {
        uint256 subSeed = uint256(keccak256(abi.encodePacked(seed, "cloth")));

        if (allowedMask == 0) {
            return _clothingColor(subSeed % NUM_CLOTHING_COLORS);
        }

        uint256 count = 0;
        for (uint256 i = 0; i < NUM_CLOTHING_COLORS; i++) {
            if (allowedMask & (uint16(1) << uint16(i)) != 0) count++;
        }

        uint256 pick = subSeed % count;
        uint256 j = 0;
        for (uint256 i = 0; i < NUM_CLOTHING_COLORS; i++) {
            if (allowedMask & (uint16(1) << uint16(i)) != 0) {
                if (j == pick) return _clothingColor(i);
                j++;
            }
        }

        return _clothingColor(0);
    }
}
