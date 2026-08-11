// SPDX-License-Identifier: MIT

library FixedPoint {
    uint64 internal constant WAD = 1000000000000000000;
    uint64 internal constant BPS = 10000;
    uint64 internal constant USDC_SCALE = 1000000000000;

    function usdcToWad(uint64 amount) internal pure returns (uint64) {
        return amount * USDC_SCALE;
    }

    function wadToUsdc(uint64 amount) internal pure returns (uint64) {
        return amount / USDC_SCALE;
    }

    function mulDiv(uint64 x, uint64 y, uint64 denominator) internal pure returns (uint64) {
        return uint64((uint128(x) * uint128(y)) / uint128(denominator));
    }

    function bpsOf(uint64 amount, uint64 bps) internal pure returns (uint64) {
        return amount * bps / BPS;
    }
}