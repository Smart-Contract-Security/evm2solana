// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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
        require(denominator > 0, "division by zero");
        if (x == 0 || y == 0) {
            return 0;
        }
        uint256 xy = x * y;
        require(xy / x == y, "multiplication overflow");
        return xy / denominator;
    }

    function bpsOf(uint256 amount, uint256 bps) internal pure returns (uint256) {
        return amount * bps / BPS;
    }
}