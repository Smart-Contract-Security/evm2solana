// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title FixedPoint
library FixedPoint {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant BPS = 10_000;
    uint256 internal constant USDC_SCALE = 1e12;

    function usdcToWad(uint256 amount) internal pure returns (uint256) {
        return amount * USDC_SCALE;
    }

    function wadToUsdc(uint256 amount) internal pure returns (uint256) {
        return amount / USDC_SCALE;
    }

    function mulDiv(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256) {
        return Math.mulDiv(x, y, denominator);
    }

    function bpsOf(uint256 amount, uint256 bps) internal pure returns (uint256) {
        return amount * bps / BPS;
    }
}
