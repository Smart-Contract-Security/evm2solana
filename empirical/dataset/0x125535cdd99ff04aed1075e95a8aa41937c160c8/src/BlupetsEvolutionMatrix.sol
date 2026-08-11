// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

library BlupetsEvolutionMatrix {
    uint8 internal constant STAGE_T1 = 1;
    uint8 internal constant STAGE_T2 = 2;
    uint8 internal constant STAGE_T3 = 3;
    uint8 internal constant STAGE_T4 = 4;
    uint8 internal constant BASE_LINEAGE_COUNT = 8;
    uint8 internal constant FAMILY_LINEAGE_COUNT = 36;
    uint8 internal constant T2_FORM_COUNT = 5;
    uint8 internal constant T3_FORM_COUNT = 3;
    uint8 internal constant T4_FORM_COUNT = 1;

    error InvalidBaseLineage();
    error InvalidFamilyLineage();
    error InvalidMergeStage();
    error IncompatibleLineage();

    function mergeLineage(uint8 stage, uint8 keeperLineage, uint8 burnerLineage) internal pure returns (uint8) {
        if (stage == STAGE_T1) return familyLineageForBasePair(keeperLineage, burnerLineage);
        if (stage == STAGE_T2 || stage == STAGE_T3) {
            if (keeperLineage >= FAMILY_LINEAGE_COUNT || burnerLineage >= FAMILY_LINEAGE_COUNT) {
                revert InvalidFamilyLineage();
            }
            if (keeperLineage != burnerLineage) revert IncompatibleLineage();
            return keeperLineage;
        }
        revert InvalidMergeStage();
    }

    function rollForm(uint8 nextStage, uint256 randomWord) internal pure returns (uint8) {
        // forge-lint: disable-next-line(unsafe-typecast)
        if (nextStage == STAGE_T2) return uint8(randomWord % T2_FORM_COUNT);
        // forge-lint: disable-next-line(unsafe-typecast)
        if (nextStage == STAGE_T3) return uint8(randomWord % T3_FORM_COUNT);
        if (nextStage == STAGE_T4) return 0;
        revert InvalidMergeStage();
    }

    function familyLineageForBasePair(uint8 a, uint8 b) internal pure returns (uint8) {
        if (a >= BASE_LINEAGE_COUNT || b >= BASE_LINEAGE_COUNT) revert InvalidBaseLineage();
        if (a == b) return a;
        if (a > b) {
            uint8 tmp = a;
            a = b;
            b = tmp;
        }

        uint8 offset = 0;
        for (uint8 i = 0; i < a; i++) {
            offset += BASE_LINEAGE_COUNT - 1 - i;
        }

        return BASE_LINEAGE_COUNT + offset + (b - a - 1);
    }

    function baseLineageCount() internal pure returns (uint8) {
        return BASE_LINEAGE_COUNT;
    }

    function familyLineageCount() internal pure returns (uint8) {
        return FAMILY_LINEAGE_COUNT;
    }
}
