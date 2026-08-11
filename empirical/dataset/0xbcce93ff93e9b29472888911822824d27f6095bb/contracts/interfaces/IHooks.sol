// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PoolKey, PoolId} from "./PoolKey.sol";
import {IPoolManager} from "./IPoolManager.sol";

/// @notice Hooks permission flags — determines which hook callbacks are active
library Hooks {
    struct Permissions {
        bool beforeInitialize;
        bool afterInitialize;
        bool beforeAddLiquidity;
        bool afterAddLiquidity;
        bool beforeRemoveLiquidity;
        bool afterRemoveLiquidity;
        bool beforeSwap;
        bool afterSwap;
        bool beforeDonate;
        bool afterDonate;
        bool beforeSwapReturnDelta;
        bool afterSwapReturnDelta;
        bool afterAddLiquidityReturnDelta;
        bool afterRemoveLiquidityReturnDelta;
    }
}

/// @notice Library for LP fee flags used in Uniswap V4
library LPFeeLibrary {
    /// @notice Flag to indicate a pool has a dynamic fee (set in PoolKey.fee)
    uint24 internal constant DYNAMIC_FEE_FLAG  = 0x800000;

    /// @notice Flag to indicate the hook is overriding the LP fee on a per-swap basis
    uint24 internal constant OVERRIDE_FEE_FLAG = 0x400000;
}

/// @notice Minimal interface for Uniswap V4 Hooks contract
interface IHooks {
    /// @notice Called before a pool is initialized
    function beforeInitialize(
        address sender,
        PoolKey calldata key,
        uint160 sqrtPriceX96
    ) external returns (bytes4);

    /// @notice Called after a pool is initialized
    function afterInitialize(
        address sender,
        PoolKey calldata key,
        uint160 sqrtPriceX96,
        int24 tick
    ) external returns (bytes4);

    /// @notice Called before a swap is executed
    function beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) external returns (bytes4, int256, uint24);

    /// @notice Called after a swap is executed
    function afterSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        int256 delta,
        bytes calldata hookData
    ) external returns (bytes4, int128);
}
