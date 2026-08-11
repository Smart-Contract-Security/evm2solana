// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title ScoringTypes
/// @notice Score-weight + polarity tables for the 18 tracked stats.
/// Weights are 1e6-scaled; polarities are int8 {+1, -1}.
///
/// Whitepaper §06 (live values):
///   MP +0.05  GLS +3   AST +2   SH +0.5  SOT +1   ATT +0.05
///   CMP +0.08 CMP% +1  TKL +1   INT +1   CLR +0.7 AER +1
///   SV +1.5   GA −3    CS +5    YC −2    RC −5    OG −5
library ScoringTypes {
    uint32 internal constant SCALE = 1_000_000;  // 1e6

    function statWeights() internal pure returns (uint32[18] memory w) {
        w[0]  =       50_000;   // MP   ×0.05
        w[1]  =    3_000_000;   // GLS  ×3
        w[2]  =    2_000_000;   // AST  ×2
        w[3]  =      500_000;   // SH   ×0.5
        w[4]  =    1_000_000;   // SOT  ×1
        w[5]  =       50_000;   // ATT  ×0.05
        w[6]  =       80_000;   // CMP  ×0.08
        w[7]  =    1_000_000;   // CMP% ×1
        w[8]  =    1_000_000;   // TKL  ×1
        w[9]  =    1_000_000;   // INT  ×1
        w[10] =      700_000;   // CLR  ×0.7
        w[11] =    1_000_000;   // AER  ×1
        w[12] =    1_500_000;   // SV   ×1.5
        w[13] =    3_000_000;   // GA   ×3   (polarity −)
        w[14] =    5_000_000;   // CS   ×5
        w[15] =    2_000_000;   // YC   ×2   (polarity −)
        w[16] =    5_000_000;   // RC   ×5   (polarity −)
        w[17] =    5_000_000;   // OG   ×5   (polarity −)
    }

    function statPolarities() internal pure returns (int8[18] memory p) {
        for (uint256 i = 0; i < 18; ++i) p[i] = 1;
        p[13] = -1;  // GA
        p[15] = -1;  // YC
        p[16] = -1;  // RC
        p[17] = -1;  // OG
    }

    /// @dev Rarity multipliers, 1e6-scaled. Default schedule.
    function rarityMultiplier(uint8 rarity) internal pure returns (uint32) {
        if (rarity == 0) return 1_000_000;   // BASE      ×1.0
        if (rarity == 1) return 1_250_000;   // RARE      ×1.25
        if (rarity == 2) return 1_500_000;   // MYTHIC    ×1.5
        if (rarity == 3) return 2_000_000;   // LEGENDARY ×2.0
        revert("rarity oob");
    }
}
