// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IHatCard} from "../card/IHatCard.sol";

/// @title PackTiers
/// @notice Static metadata for the 4 pack tiers from whitepaper §04.
///
/// Pity floors:
///   SINGLE     1 pull, no floor
///   STARTER    5 pulls, guaranteed RARE+
///   ELITE      20 pulls, guaranteed MYTHIC+
///   APEX       50 pulls, guaranteed LEGENDARY+
///
/// Rarity weights at draw time (out of 100, whitepaper §04):
///   BASE 55, RARE 27, MYTHIC 14, LEGENDARY 4
library PackTiers {
    enum Tier { SINGLE, STARTER, ELITE, APEX }

    uint8 internal constant W_BASE      = 55;
    uint8 internal constant W_RARE      = 27;
    uint8 internal constant W_MYTHIC    = 14;
    uint8 internal constant W_LEGENDARY = 4;
    uint8 internal constant W_TOTAL     = 100;

    function pulls(Tier t) internal pure returns (uint8) {
        if (t == Tier.SINGLE)  return 1;
        if (t == Tier.STARTER) return 5;
        if (t == Tier.ELITE)   return 20;
        if (t == Tier.APEX)    return 50;
        revert("PackTiers: unknown");
    }

    /// @dev Minimum rarity guaranteed by the tier. SINGLE has no floor; we
    /// model that as BASE (which the standard draw can always satisfy).
    function floor(Tier t) internal pure returns (IHatCard.Rarity) {
        if (t == Tier.SINGLE)  return IHatCard.Rarity.BASE;
        if (t == Tier.STARTER) return IHatCard.Rarity.RARE;
        if (t == Tier.ELITE)   return IHatCard.Rarity.MYTHIC;
        if (t == Tier.APEX)    return IHatCard.Rarity.LEGENDARY;
        revert("PackTiers: unknown");
    }

    /// @dev Weighted draw over the four tiers. Pass `r ∈ [0, 100)`.
    function drawRarity(uint256 r) internal pure returns (IHatCard.Rarity) {
        if (r < W_BASE) return IHatCard.Rarity.BASE;
        r -= W_BASE;
        if (r < W_RARE) return IHatCard.Rarity.RARE;
        r -= W_RARE;
        if (r < W_MYTHIC) return IHatCard.Rarity.MYTHIC;
        return IHatCard.Rarity.LEGENDARY;
    }
}
