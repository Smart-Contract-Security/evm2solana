// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title TickMathLib
/// @notice Price/tick math extracted from TokenFactory to reduce contract size.
///         Adapted from Uniswap V3 TickMath.getTickAtSqrtRatio.
library TickMathLib {
    /// @dev Converts sqrtPriceX96 to tick.
    function sqrtPriceX96ToTick(uint160 sqrtPriceX96) internal pure returns (int24 tick) {
        require(sqrtPriceX96 >= 4295128739 && sqrtPriceX96 < 1461446703485210103287273052203988822378723970342, "sqrtPrice OOB");

        uint256 ratio = uint256(sqrtPriceX96) << 32;

        uint256 r = ratio;
        uint256 msb = 0;

        assembly {
            let f := shl(7, gt(r, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := shl(6, gt(r, 0xFFFFFFFFFFFFFFFF))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := shl(5, gt(r, 0xFFFFFFFF))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := shl(4, gt(r, 0xFFFF))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := shl(3, gt(r, 0xFF))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := shl(2, gt(r, 0xF))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := shl(1, gt(r, 0x3))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := gt(r, 0x1)
            msb := or(msb, f)
        }

        if (msb >= 128) r = ratio >> (msb - 127);
        else r = ratio << (127 - msb);

        int256 log_2 = (int256(msb) - 128) << 64;

        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(63, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(62, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(61, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(60, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(59, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(58, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(57, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(56, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(55, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(54, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(53, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(52, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(51, f))
            r := shr(f, r)
        }

        int256 log_sqrt10001 = log_2 * 255738958999603826347141;

        tick = int24((log_sqrt10001 - 3402992956809132418596140100660247210) >> 128);
    }

    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }

    function calculateMcapSqrtPrice(
        bool wethIsToken0,
        uint256 totalSupply,
        uint256 marketCap,
        uint256 ethPriceUSD
    ) internal pure returns (uint160) {
        if (ethPriceUSD < 100 * 10**18 || ethPriceUSD > 100000 * 10**18) {
            ethPriceUSD = 3000 * 10**18;
        }

        uint256 marketCapInETH = (marketCap * 10**18) / ethPriceUSD;

        if (wethIsToken0) {
            uint256 sqrtSupply = sqrt(totalSupply);
            uint256 sqrtMarketCapETH = sqrt(marketCapInETH);
            return uint160((sqrtSupply * 2**96) / sqrtMarketCapETH);
        } else {
            uint256 sqrtMarketCapETH = sqrt(marketCapInETH);
            uint256 sqrtSupply = sqrt(totalSupply);
            return uint160((sqrtMarketCapETH * 2**96) / sqrtSupply);
        }
    }

    function getOptimalTickRange(
        uint256 targetMcap,
        uint256 MCAP_1,
        uint256 MCAP_2,
        uint256 MCAP_3
    ) internal pure returns (int24) {
        if (targetMcap == MCAP_1) return int24(230000);
        if (targetMcap == MCAP_2) return int24(215000);
        if (targetMcap == MCAP_3) return int24(200000);
        return int24(184000);
    }

    function getInitialTick(
        uint256 totalSupply,
        uint256 targetMarketCap,
        int24 tickSpacing,
        uint256 ethPriceUSD
    ) internal pure returns (int24) {
        return getInitialTick(totalSupply, targetMarketCap, tickSpacing, ethPriceUSD, true);
    }

    function getInitialTick(
        uint256 totalSupply,
        uint256 targetMarketCap,
        int24 tickSpacing,
        uint256 ethPriceUSD,
        bool wethIsToken0
    ) internal pure returns (int24) {
        uint160 sqrtPriceX96 = calculateMcapSqrtPrice(wethIsToken0, totalSupply, targetMarketCap, ethPriceUSD);
        int24 tick = sqrtPriceX96ToTick(sqrtPriceX96);

        if (tick < 0) {
            tick = (tick - tickSpacing + 1) / tickSpacing * tickSpacing;
        } else {
            tick = (tick / tickSpacing) * tickSpacing;
        }

        return tick;
    }
}
