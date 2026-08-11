// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/*
 * ██╗░░██████╗░██████╗░░█████╗░██╗░░░██╗
 * ██║░░██╔══██╗██╔══██╗██╔══██╗╚██╗░██╔╝
 * ██║░░██████╔╝██████╔╝███████║░╚████╔╝░
 * ╚═╝░░██╔═══╝░██╔══██╗██╔══██║░░╚██╔╝░░
 * ██╗░░██║░░░░░██║░░██║██║░░██║░░░██║░░░
 * ╚═╝░░╚═╝░░░░░╚═╝░░╚═╝╚═╝░░╚═╝░░░╚═╝░░░
 */

/**
 * @title Uniswap Position Helper
 * @notice Calculates position values for both Uniswap V3 and V4 protocols
 */
contract UniswapPositionHelper {
    /// @notice Contract version
    uint256 public constant VERSION = 2;

    /// @notice Storage slot for pools mapping in V4 PoolManager
    bytes32 private constant POOLS_SLOT = bytes32(uint256(6));

    /// @notice Bit offsets for tick extraction from V4 PositionInfo
    uint8 internal constant TICK_LOWER_OFFSET = 8;
    uint8 internal constant TICK_UPPER_OFFSET = 32;

    /// @notice Fixed-point math constants
    uint256 private constant Q96 = 2**96;
    uint256 private constant Q192 = 2**192;

    struct Position {
        uint256 token0Amount;
        uint256 token1Amount;
        address token0;
        address token1;
        uint128 liquidity;
        uint256 totalValue;
    }

    /**
     * @notice Extract tickLower from V4 PositionInfo using assembly
     */
    function tickLower(PositionInfo info) internal pure returns (int24 _tickLower) {
        assembly ("memory-safe") {
            _tickLower := signextend(2, shr(TICK_LOWER_OFFSET, info))
        }
    }

    /**
     * @notice Extract tickUpper from V4 PositionInfo using assembly
     */
    function tickUpper(PositionInfo info) internal pure returns (int24 _tickUpper) {
        assembly ("memory-safe") {
            _tickUpper := signextend(2, shr(TICK_UPPER_OFFSET, info))
        }
    }

    /**
     * @notice Get the storage slot for V4 pool state
     */
    function _getPoolStateSlot(PoolId poolId) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(PoolId.unwrap(poolId), POOLS_SLOT));
    }

    /**
     * @notice Get V4 pool state using low-level storage access
     */
    function getSlot0(IPoolManager manager, PoolId poolId)
        internal
        view
        returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee)
    {
        bytes32 stateSlot = _getPoolStateSlot(poolId);
        bytes32 data = manager.extsload(stateSlot);

        assembly ("memory-safe") {
            sqrtPriceX96 := and(data, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
            tick := signextend(2, shr(160, data))
            protocolFee := and(shr(184, data), 0xFFFFFF)
            lpFee := and(shr(208, data), 0xFFFFFF)
        }
    }

    /// @dev Calculates `floor(x * y / d)` with full precision.
    /// Throws if result overflows a uint256 or when `d` is zero.
    /// Credit to Remco Bloemen under MIT license: https://2π.com/21/muldiv
    function _mulDiv(uint256 x, uint256 y, uint256 d) internal pure returns (uint256 z) {
        /// @solidity memory-safe-assembly
        assembly {
            // 512-bit multiply `[p1 p0] = x * y`.
            // Compute the product mod `2**256` and mod `2**256 - 1`
            // then use the Chinese Remainder Theorem to reconstruct
            // the 512 bit result. The result is stored in two 256
            // variables such that `product = p1 * 2**256 + p0`.

            // Temporarily use `z` as `p0` to save gas.
            z := mul(x, y) // Lower 256 bits of `x * y`.
            for {} 1 {} {
                // If overflows.
                if iszero(mul(or(iszero(x), eq(div(z, x), y)), d)) {
                    let mm := mulmod(x, y, not(0))
                    let p1 := sub(mm, add(z, lt(mm, z))) // Upper 256 bits of `x * y`.

                    /*------------------- 512 by 256 division --------------------*/

                    // Make division exact by subtracting the remainder from `[p1 p0]`.
                    let r := mulmod(x, y, d) // Compute remainder using mulmod.
                    let t := and(d, sub(0, d)) // The least significant bit of `d`. `t >= 1`.
                    // Make sure `z` is less than `2**256`. Also prevents `d == 0`.
                    // Placing the check here seems to give more optimal stack operations.
                    if iszero(gt(d, p1)) {
                        mstore(0x00, 0xae47f702) // `FullMulDivFailed()`.
                        revert(0x1c, 0x04)
                    }
                    d := div(d, t) // Divide `d` by `t`, which is a power of two.
                    // Invert `d mod 2**256`
                    // Now that `d` is an odd number, it has an inverse
                    // modulo `2**256` such that `d * inv = 1 mod 2**256`.
                    // Compute the inverse by starting with a seed that is correct
                    // correct for four bits. That is, `d * inv = 1 mod 2**4`.
                    let inv := xor(2, mul(3, d))
                    // Now use Newton-Raphson iteration to improve the precision.
                    // Thanks to Hensel's lifting lemma, this also works in modular
                    // arithmetic, doubling the correct bits in each step.
                    inv := mul(inv, sub(2, mul(d, inv))) // inverse mod 2**8
                    inv := mul(inv, sub(2, mul(d, inv))) // inverse mod 2**16
                    inv := mul(inv, sub(2, mul(d, inv))) // inverse mod 2**32
                    inv := mul(inv, sub(2, mul(d, inv))) // inverse mod 2**64
                    inv := mul(inv, sub(2, mul(d, inv))) // inverse mod 2**128
                    z :=
                        mul(
                            // Divide [p1 p0] by the factors of two.
                            // Shift in bits from `p1` into `p0`. For this we need
                            // to flip `t` such that it is `2**256 / t`.
                            or(mul(sub(p1, gt(r, z)), add(div(sub(0, t), t), 1)), div(sub(z, r), t)),
                            mul(sub(2, mul(d, inv)), inv) // inverse mod 2**256
                        )
                    break
                }
                z := div(z, d)
                break
            }
        }
    }

    /**
     * @notice Calculate position value for Uniswap V3 positions
     * @param positionManager V3 position manager address
     * @param poolAddress V3 pool address
     * @param tokenId Position token ID
     * @param valueInToken0 Whether to express total value in token0 or token1
     */
    function getV3Position(
        address positionManager,
        address poolAddress,
        uint256 tokenId,
        bool valueInToken0
    ) external view returns (Position memory result) {
        require(
            positionManager != address(0) && poolAddress != address(0) && tokenId > 0,
            "Invalid inputs"
        );

        (,, address token0, address token1,, int24 _tickLower, int24 _tickUpper, uint128 liquidity,,,,) =
            IV3NonfungiblePositionManager(positionManager).positions(tokenId);

        require(token0 != address(0), "Position does not exist");

        (uint160 sqrtPriceX96, int24 currentTick,,,,,) = IV3Pool(poolAddress).slot0();

        result.token0 = token0;
        result.token1 = token1;
        result.liquidity = liquidity;

        uint160 sqrtPriceLowerX96 = _getSqrtRatioAtTick(_tickLower);
        uint160 sqrtPriceUpperX96 = _getSqrtRatioAtTick(_tickUpper);

        if (currentTick < _tickLower) {
            // Position entirely in token0
            uint256 priceDiff = sqrtPriceUpperX96 - sqrtPriceLowerX96;
            result.token0Amount = _mulDiv(_mulDiv(uint256(liquidity), priceDiff, sqrtPriceUpperX96), Q96, sqrtPriceLowerX96);
            result.token1Amount = 0;
            result.totalValue = valueInToken0 ? result.token0Amount 
                : _mulDiv(result.token0Amount, uint256(sqrtPriceX96) * sqrtPriceX96, Q192);
        } else if (currentTick >= _tickUpper) {
            // Position entirely in token1
            result.token0Amount = 0;
            result.token1Amount = _mulDiv(uint256(liquidity), sqrtPriceUpperX96 - sqrtPriceLowerX96, Q96);
            result.totalValue = valueInToken0 
                ? _mulDiv(result.token1Amount, Q192, uint256(sqrtPriceX96) * sqrtPriceX96) : result.token1Amount;
        } else {
            // Position spans current tick
            result.token0Amount = _mulDiv(_mulDiv(uint256(liquidity), sqrtPriceUpperX96 - sqrtPriceX96, sqrtPriceUpperX96), 
                Q96, sqrtPriceX96);
            result.token1Amount = _mulDiv(uint256(liquidity), sqrtPriceX96 - sqrtPriceLowerX96, Q96);

            if (valueInToken0) {
                uint256 token1InToken0 = _mulDiv(result.token1Amount, Q192, uint256(sqrtPriceX96) * sqrtPriceX96);
                result.totalValue = result.token0Amount + token1InToken0;
            } else {
                uint256 token0InToken1 = _mulDiv(result.token0Amount, uint256(sqrtPriceX96) * sqrtPriceX96, Q192);
                result.totalValue = result.token1Amount + token0InToken1;
            }
        }
    }

    /**
     * @notice Calculate position value for Uniswap V4 positions
     * @param positionManager V4 position manager address
     * @param poolManager V4 pool manager address
     * @param tokenId Position token ID
     * @param valueInToken0 Whether to express total value in token0 or token1
     */
    function getV4Position(
        address positionManager,
        address poolManager,
        uint256 tokenId,
        bool valueInToken0
    ) external view returns (Position memory result) {
        require(
            positionManager != address(0) && poolManager != address(0) && tokenId > 0,
            "Invalid inputs"
        );

        uint128 liquidity = IV4PositionManager(positionManager).getPositionLiquidity(tokenId);
        require(liquidity > 0, "Position does not exist");

        (PoolKey memory poolKey, PositionInfo positionInfo) = 
            IV4PositionManager(positionManager).getPoolAndPositionInfo(tokenId);

        result.token0 = Currency.unwrap(poolKey.currency0);
        result.token1 = Currency.unwrap(poolKey.currency1);
        result.liquidity = liquidity;

        PoolId poolId = PoolId.wrap(keccak256(abi.encode(poolKey)));
        (uint160 sqrtPriceX96, int24 currentTick,,) = getSlot0(IPoolManager(poolManager), poolId);

        int24 _tickLower = tickLower(positionInfo);
        int24 _tickUpper = tickUpper(positionInfo);
        require(_tickLower < _tickUpper && _tickLower >= -887272 && _tickUpper <= 887272, "Invalid ticks");

        uint160 sqrtPriceLowerX96 = _getSqrtRatioAtTick(_tickLower);
        uint160 sqrtPriceUpperX96 = _getSqrtRatioAtTick(_tickUpper);

        if (currentTick < _tickLower) {
            // Position entirely in token0
            uint256 priceDiff = sqrtPriceUpperX96 - sqrtPriceLowerX96;
            result.token0Amount = _mulDiv(_mulDiv(uint256(liquidity), priceDiff, sqrtPriceUpperX96), Q96, sqrtPriceLowerX96);
            result.token1Amount = 0;
            result.totalValue = valueInToken0 ? result.token0Amount 
                : _mulDiv(result.token0Amount, uint256(sqrtPriceX96) * sqrtPriceX96, Q192);
        } else if (currentTick >= _tickUpper) {
            // Position entirely in token1
            result.token0Amount = 0;
            result.token1Amount = _mulDiv(uint256(liquidity), sqrtPriceUpperX96 - sqrtPriceLowerX96, Q96);
            result.totalValue = valueInToken0 
                ? _mulDiv(result.token1Amount, Q192, uint256(sqrtPriceX96) * sqrtPriceX96) : result.token1Amount;
        } else {
            // Position spans current tick
            result.token0Amount = _mulDiv(_mulDiv(uint256(liquidity), sqrtPriceUpperX96 - sqrtPriceX96, sqrtPriceUpperX96), 
                Q96, sqrtPriceX96);
            result.token1Amount = _mulDiv(uint256(liquidity), sqrtPriceX96 - sqrtPriceLowerX96, Q96);

            if (valueInToken0) {
                uint256 token1InToken0 = _mulDiv(result.token1Amount, Q192, uint256(sqrtPriceX96) * sqrtPriceX96);
                result.totalValue = result.token0Amount + token1InToken0;
            } else {
                uint256 token0InToken1 = _mulDiv(result.token0Amount, uint256(sqrtPriceX96) * sqrtPriceX96, Q192);
                result.totalValue = result.token1Amount + token0InToken1;
            }
        }
    }

    /**
     * @notice Calculate sqrt ratio from tick using Uniswap's TickMath formula
     */
    function _getSqrtRatioAtTick(int24 tick) internal pure returns (uint160 sqrtPriceX96) {
        require(tick >= -887272 && tick <= 887272, "T");

        uint256 absTick = tick < 0 ? uint256(-int256(tick)) : uint256(int256(tick));
        uint256 ratio = absTick & 0x1 != 0 ? 0xfffcb933bd6fad37aa2d162d1a594001 : 0x100000000000000000000000000000000;

        if (absTick & 0x2 != 0) ratio = (ratio * 0xfff97272373d413259a46990580e213a) >> 128;
        if (absTick & 0x4 != 0) ratio = (ratio * 0xfff2e50f5f656932ef12357cf3c7fdcc) >> 128;
        if (absTick & 0x8 != 0) ratio = (ratio * 0xffe5caca7e10e4e61c3624eaa0941cd0) >> 128;
        if (absTick & 0x10 != 0) ratio = (ratio * 0xffcb9843d60f6159c9db58835c926644) >> 128;
        if (absTick & 0x20 != 0) ratio = (ratio * 0xff973b41fa98c081472e6896dfb254c0) >> 128;
        if (absTick & 0x40 != 0) ratio = (ratio * 0xff2ea16466c96a3843ec78b326b52861) >> 128;
        if (absTick & 0x80 != 0) ratio = (ratio * 0xfe5dee046a99a2a811c461f1969c3053) >> 128;
        if (absTick & 0x100 != 0) ratio = (ratio * 0xfcbe86c7900a88aedcffc83b479aa3a4) >> 128;
        if (absTick & 0x200 != 0) ratio = (ratio * 0xf987a7253ac413176f2b074cf7815e54) >> 128;
        if (absTick & 0x400 != 0) ratio = (ratio * 0xf3392b0822b70005940c7a398e4b70f3) >> 128;
        if (absTick & 0x800 != 0) ratio = (ratio * 0xe7159475a2c29b7443b29c7fa6e889d9) >> 128;
        if (absTick & 0x1000 != 0) ratio = (ratio * 0xd097f3bdfd2022b8845ad8f792aa5825) >> 128;
        if (absTick & 0x2000 != 0) ratio = (ratio * 0xa9f746462d870fdf8a65dc1f90e061e5) >> 128;
        if (absTick & 0x4000 != 0) ratio = (ratio * 0x70d869a156d2a1b890bb3df62baf32f7) >> 128;
        if (absTick & 0x8000 != 0) ratio = (ratio * 0x31be135f97d08fd981231505542fcfa6) >> 128;
        if (absTick & 0x10000 != 0) ratio = (ratio * 0x9aa508b5b7a84e1c677de54f3e99bc9) >> 128;
        if (absTick & 0x20000 != 0) ratio = (ratio * 0x5d6af8dedb81196699c329225ee604) >> 128;
        if (absTick & 0x40000 != 0) ratio = (ratio * 0x2216e584f5fa1ea926041bedfe98) >> 128;
        if (absTick & 0x80000 != 0) ratio = (ratio * 0x48a170391f7dc42444e8fa2) >> 128;

        if (tick > 0) ratio = type(uint256).max / ratio;
        sqrtPriceX96 = uint160((ratio >> 32) + (ratio % (1 << 32) == 0 ? 0 : 1));
    }
}

// Types and interfaces
type PositionInfo is uint256;
type Currency is address;
type PoolId is bytes32;

struct PoolKey {
    Currency currency0;
    Currency currency1;
    uint24 fee;
    int24 tickSpacing;
    IHooks hooks;
}

interface IV3NonfungiblePositionManager {
    function positions(uint256) external view returns (
        uint96, address, address, address, uint24, int24, int24, uint128, uint256, uint256, uint128, uint128
    );
}

interface IV3Pool {
    function slot0() external view returns (uint160, int24, uint16, uint16, uint16, uint8, bool);
}

interface IV4PositionManager {
    function getPoolAndPositionInfo(uint256) external view returns (PoolKey memory, PositionInfo);
    function getPositionLiquidity(uint256) external view returns (uint128);
}

interface IPoolManager {
    function extsload(bytes32 slot) external view returns (bytes32);
}

interface IHooks {}