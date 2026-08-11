// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library TierMath {
    uint256 internal constant RATE_VECTOR_0 = 0;
    uint256 internal constant RATE_VECTOR_1 = 1;
    uint256 internal constant RATE_VECTOR_2 = 2;
    uint256 internal constant RATE_VECTOR_3 = 3;

    function tierRate(uint8 tier, uint256 epochIndex) internal pure returns (uint256) {
        uint256 idx = (uint256(tier - 1) + 4 - (epochIndex % 4)) % 4;
        if (idx == 0) return RATE_VECTOR_0;
        if (idx == 1) return RATE_VECTOR_1;
        if (idx == 2) return RATE_VECTOR_2;
        return RATE_VECTOR_3;
    }

    function tierFromTokenId(uint256 tokenId) internal pure returns (uint8) {
        return uint8(((tokenId - 1) % 4) + 1);
    }
}
