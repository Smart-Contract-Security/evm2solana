// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IUniswapV3Pool {
    function slot0() external view returns (
        uint160 sqrtPriceX96,
        int24 tick,
        uint16 observationIndex,
        uint16 observationCardinality,
        uint16 observationCardinalityNext,
        uint8 feeProtocol,
        bool unlocked
    );
    function liquidity() external view returns (uint128);
    function feeGrowthGlobal0X128() external view returns (uint256);
    function feeGrowthGlobal1X128() external view returns (uint256);
    function protocolFees() external view returns (uint128 token0, uint128 token1);
    function tickSpacing() external view returns (int24);
    function tickBitmap(int16 wordPosition) external view returns (uint256);
    function ticks(int24 tick) external view returns (
        uint128 liquidityGross,
        int128 liquidityNet,
        uint256 feeGrowthOutside0X128,
        uint256 feeGrowthOutside1X128,
        int56 tickCumulativeOutside,
        uint160 secondsPerLiquidityOutsideX128,
        uint32 secondsOutside,
        bool initialized
    );
    function observations(uint256 index) external view returns (
        uint32 blockTimestamp,
        int56 tickCumulative,
        uint160 secondsPerLiquidityCumulativeX128,
        bool initialized
    );
    function fee() external view returns (uint24);
}

contract UniswapV3PoolInfo {
    struct PoolData {
        SlotData slotData;
        OtherPoolData otherPoolData;
        TickData tickData;
        Observation[] observations;
    }

    struct SlotData {
        uint160 sqrtPriceX96;
        int24 tick;
        uint16 observationIndex;
        uint16 observationCardinality;
        uint16 observationCardinalityNext;
        uint8 feeProtocol;
        bool unlocked;
    }

    struct OtherPoolData {
        uint128 liquidity;
        uint256 feeGrowthGlobal0X128;
        uint256 feeGrowthGlobal1X128;
        uint128 protocolFeesToken0;
        uint128 protocolFeesToken1;
        int24 tickSpacing;
        uint24 fee;
    }

    struct TickData {
        TickInfo[] initializedTicks;
        uint256[] tickBitmaps;
    }

    struct TickInfo {
        int24 tick;
        uint128 liquidityGross;
        int128 liquidityNet;
        uint256 feeGrowthOutside0X128;
        uint256 feeGrowthOutside1X128;
        int56 tickCumulativeOutside;
        uint160 secondsPerLiquidityOutsideX128;
        uint32 secondsOutside;
        bool initialized;
    }

    struct Observation {
        uint32 blockTimestamp;
        int56 tickCumulative;
        uint160 secondsPerLiquidityCumulativeX128;
        bool initialized;
    }

    function getPoolData(address poolAddress) external view returns (PoolData memory) {
        SlotData memory slotData = getSlotData(poolAddress);
        OtherPoolData memory otherPoolData = getOtherPoolData(poolAddress);
        TickData memory tickData = getTickData(poolAddress, slotData.tick);
        Observation[] memory observations = getObservations(poolAddress, slotData.observationCardinality);

        return PoolData({
            slotData: slotData,
            otherPoolData: otherPoolData,
            tickData: tickData,
            observations: observations
        });
    }

    function getSlotData(address poolAddress) internal view returns (SlotData memory) {
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        ) = pool.slot0();

        return SlotData({
            sqrtPriceX96: sqrtPriceX96,
            tick: tick,
            observationIndex: observationIndex,
            observationCardinality: observationCardinality,
            observationCardinalityNext: observationCardinalityNext,
            feeProtocol: feeProtocol,
            unlocked: unlocked
        });
    }

    function getOtherPoolData(address poolAddress) internal view returns (OtherPoolData memory) {
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        (uint128 protocolFeesToken0, uint128 protocolFeesToken1) = pool.protocolFees();
        return OtherPoolData({
            liquidity: pool.liquidity(),
            feeGrowthGlobal0X128: pool.feeGrowthGlobal0X128(),
            feeGrowthGlobal1X128: pool.feeGrowthGlobal1X128(),
            protocolFeesToken0: protocolFeesToken0,
            protocolFeesToken1: protocolFeesToken1,
            tickSpacing: pool.tickSpacing(),
            fee: pool.fee()
        });
    }

    function getTickData(address poolAddress, int24 currentTick) internal view returns (TickData memory) {
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);

        int16[] memory wordPositions = getWordPositions(currentTick);
        uint256[] memory tickBitmaps = new uint256[](wordPositions.length);
        uint256 tickCount = 0;
        for (uint256 i = 0; i < wordPositions.length; i++) {
            uint256 bitmap = pool.tickBitmap(wordPositions[i]);
            tickBitmaps[i] = bitmap;
            tickCount += countInitializedTicks(bitmap);
        }

        TickInfo[] memory ticks = new TickInfo[](tickCount > 0 ? tickCount : 1);
        if (tickCount > 0) {
            uint256 index = 0;
            for (uint256 i = 0; i < wordPositions.length; i++) {
                uint256 bitmap = tickBitmaps[i];
                index = populateTicks(pool, bitmap, wordPositions[i], ticks, index);
            }
        } else {
            // Fallback: populate with a dummy tick if no initialized ticks found
            ticks[0] = TickInfo({
                tick: currentTick,
                liquidityGross: 0,
                liquidityNet: 0,
                feeGrowthOutside0X128: 0,
                feeGrowthOutside1X128: 0,
                tickCumulativeOutside: 0,
                secondsPerLiquidityOutsideX128: 0,
                secondsOutside: 0,
                initialized: false
            });
        }

        return TickData({
            initializedTicks: ticks,
            tickBitmaps: tickBitmaps
        });
    }

    function getWordPositions(int24 currentTick) internal pure returns (int16[] memory) {
        int24 wordPosition = currentTick >> 8;
        int16[] memory wordPositions = new int16[](3);
        wordPositions[0] = int16(wordPosition - 1);
        wordPositions[1] = int16(wordPosition);
        wordPositions[2] = int16(wordPosition + 1);
        return wordPositions;
    }

    function countInitializedTicks(uint256 bitmap) internal pure returns (uint256) {
        uint256 count = 0;
        while (bitmap != 0) {
            bitmap &= (bitmap - 1);
            count++;
        }
        return count;
    }

    function populateTicks(
        IUniswapV3Pool pool,
        uint256 bitmap,
        int16 wordPosition,
        TickInfo[] memory ticks,
        uint256 index
    ) internal view returns (uint256) {
        for (uint256 i = 0; i < 256; i++) {
            if ((bitmap & (1 << i)) != 0) {
                int24 tickIndex = int24((int256(wordPosition) << 8) + int256(i));
                ticks[index] = getTickInfo(pool, tickIndex);
                index++;
            }
        }
        return index;
    }

    function getTickInfo(IUniswapV3Pool pool, int24 tickIndex) internal view returns (TickInfo memory) {
        (
            uint128 liquidityGross,
            int128 liquidityNet,
            uint256 feeGrowthOutside0X128,
            uint256 feeGrowthOutside1X128,
            int56 tickCumulativeOutside,
            uint160 secondsPerLiquidityOutsideX128,
            uint32 secondsOutside,
            bool initialized
        ) = pool.ticks(tickIndex);

        return TickInfo({
            tick: tickIndex,
            liquidityGross: liquidityGross,
            liquidityNet: liquidityNet,
            feeGrowthOutside0X128: feeGrowthOutside0X128,
            feeGrowthOutside1X128: feeGrowthOutside1X128,
            tickCumulativeOutside: tickCumulativeOutside,
            secondsPerLiquidityOutsideX128: secondsPerLiquidityOutsideX128,
            secondsOutside: secondsOutside,
            initialized: initialized
        });
    }

    function getObservations(address poolAddress, uint16 observationCardinality) internal view returns (Observation[] memory) {
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        Observation[] memory observations = new Observation[](observationCardinality);

        for (uint16 i = 0; i < observationCardinality; i++) {
            (
                uint32 blockTimestamp,
                int56 tickCumulative,
                uint160 secondsPerLiquidityCumulativeX128,
                bool initialized
            ) = pool.observations(i);

            observations[i] = Observation({
                blockTimestamp: blockTimestamp,
                tickCumulative: tickCumulative,
                secondsPerLiquidityCumulativeX128: secondsPerLiquidityCumulativeX128,
                initialized: initialized
            });
        }

        return observations;
    }
}