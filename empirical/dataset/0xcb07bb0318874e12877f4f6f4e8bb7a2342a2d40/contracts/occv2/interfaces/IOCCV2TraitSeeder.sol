// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CitizenTraits, FrozenIndices, MintRoll} from "../OCCV2TraitTypes.sol";

/// @title IOCCV2TraitSeeder — Dual-seed trait selection for OCC V2
/// @notice Two entry points back the OCC V2 trait pipeline:
///           • `getMintRollTraits` rolls the FULL pool (rares included) for
///             ONLY the 5 reshufflable categories (+ Hair, internally, as
///             filter context for AccessoryII). Returns indices AND weights so
///             the calling NFT contract can run its freeze decision without a
///             second registry read per category. Optimized for mint-time gas.
///           • `getTraitsForDisplay` resolves the CURRENTLY-DISPLAYED traits
///             for ALL 14 categories using a frozen-index struct + the on-the-
///             fly reshuffle seed, excluding rares and gender-/mood-
///             incompatible variants from the reshufflable categories.
///
///         `reshSeedAtMint` is passed as a separate parameter to display so
///         the seeder can re-derive the AT-MINT eyes index for the Accessory
///         category's `eyesBlockMask` filter — keeping static categories truly
///         static (deterministic from `permSeed` + `reshSeedAtMint`) regardless
///         of how many times the token has been transferred.
interface IOCCV2TraitSeeder {
    /// @notice At-mint roll, scoped to ONLY the categories that affect the
    ///         freeze decision (5 reshufflable + Hair as ctx). Returns indices
    ///         AND weights for the 5 reshufflable cats so the NFT can apply
    ///         the rare-threshold check without re-reading variants from the
    ///         registry.
    /// @param permSeed       Permanent seed (drives Hair + gender).
    /// @param reshSeedAtMint At-mint reshuffle seed (drives the 5 reshufflable
    ///                       categories' initial pick AND the at-mint mood).
    function getMintRollTraits(uint256 permSeed, uint256 reshSeedAtMint)
        external
        view
        returns (MintRoll memory);

    /// @notice At-render roll. Honors frozen indices and applies the rare /
    ///         gender / mood exclusion filters to non-frozen reshufflable slots.
    /// @param permSeed       Permanent seed.
    /// @param reshSeed       Current reshuffle seed
    ///                       (= keccak(SALT_RESH, tokenId, mintBlock, transferCount)).
    /// @param reshSeedAtMint At-mint reshuffle seed
    ///                       (= keccak(SALT_RESH, tokenId, mintBlock, 0)). Used
    ///                       to re-derive the at-mint eyes index for the static
    ///                       Accessory category's eyesBlockMask filter.
    /// @param frozen         Per-token frozen indices for the 4 reshufflable cats.
    /// @param eyesThreshold      Effective rare threshold for Eyes.
    /// @param eyebrowsThreshold  Effective rare threshold for Eyebrows.
    /// @param mouthThreshold     Effective rare threshold for Mouth.
    /// @param clothingThreshold  Effective rare threshold for Clothing.
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
    ) external view returns (CitizenTraits memory);
}
