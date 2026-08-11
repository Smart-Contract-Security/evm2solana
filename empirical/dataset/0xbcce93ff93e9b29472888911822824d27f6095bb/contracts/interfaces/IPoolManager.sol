// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PoolKey, PoolId} from "./PoolKey.sol";

/// @notice Minimal interface for Uniswap V4 PoolManager
interface IPoolManager {
    /// @notice Swap parameters passed to swap()
    struct SwapParams {
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Balance delta returned by swap()
    struct BalanceDelta {
        int128 amount0;
        int128 amount1;
    }

    /// @notice Initialize a new pool
    function initialize(PoolKey calldata key, uint160 sqrtPriceX96)
        external
        returns (int24 tick);

    /// @notice Called by hook contracts to update the dynamic LP fee for a pool
    function updateDynamicLPFee(PoolKey calldata key, uint24 newDynamicLPFee) external;

    /// @notice Unlock the pool manager — calls back to msg.sender.unlockCallback(data)
    function unlock(bytes calldata data) external returns (bytes memory);

    /// @notice Execute a swap against a pool
    /// @return swapDelta Packed BalanceDelta: upper 128 bits = amount0, lower 128 bits = amount1
    function swap(PoolKey calldata key, SwapParams calldata params, bytes calldata hookData)
        external
        returns (int256 swapDelta);

    /// @notice Sync currency balance before settling
    function sync(address currency) external;

    /// @notice Settle a currency debt (after transferring tokens to poolManager)
    function settle() external returns (uint256);

    /// @notice Take tokens owed from the pool manager
    function take(address currency, address to, uint256 amount) external;
}
