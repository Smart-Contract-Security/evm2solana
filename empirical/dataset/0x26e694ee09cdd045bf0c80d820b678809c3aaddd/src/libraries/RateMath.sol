// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

uint256 constant RATE_SCALE = 10 ** 27;
uint256 constant RATE_SCALE_TO_WAD = 10 ** 9;

library RateMath {
    /**
     * @dev Convert annual percentage rate (APR) to a per-second rate
     * @param apr The annual percentage rate (APR) scaled by RATE_SCALE
     * @return The per-second rate scaled by WAD
     */
    function aprPerSecond(uint256 apr) internal pure returns (uint256) {
        if (apr <= RATE_SCALE) return 0;
        return Math.mulDiv(apr - RATE_SCALE, 1, 365 days, Math.Rounding.Ceil) / RATE_SCALE_TO_WAD;
    }
}
