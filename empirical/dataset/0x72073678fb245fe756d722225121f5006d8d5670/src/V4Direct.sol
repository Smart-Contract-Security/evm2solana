// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

/// @title V4Direct
/// @notice Abstract base for contracts that need to swap against the Uniswap V4 PoolManager
///         WITHOUT going through the UniversalRouter. Pattern: child calls `_swapV4`, this
///         base contract becomes the locker on PoolManager, the callback runs `poolManager.swap`,
///         settles the input token via `ERC20.transfer` + `poolManager.settle`, takes the output
///         via `poolManager.take`. The output is delivered to this contract; the child reads its
///         own balance delta and uses the result however it needs.
///
///         Why not UniversalRouter? The deployed mainnet UR's V4_SWAP module rejects our encoded
///         action params (likely a v4-periphery-version mismatch between the UR-as-deployed and
///         what our local build links against). The direct pattern has no ABI surface to break.
abstract contract V4Direct is IUnlockCallback {
    using SafeERC20 for IERC20;
    using CurrencyLibrary for Currency;

    IPoolManager public immutable POOL_MANAGER;

    error V4DirectNotPoolManager();

    struct V4SwapCtx {
        PoolKey key;
        bool zeroForOne;
        int256 amountSpecified;   // negative = exact input
    }

    constructor(IPoolManager poolManager_) {
        POOL_MANAGER = poolManager_;
    }

    /// @notice Run an exact-input single-hop V4 swap. The input token must already be at
    ///         `address(this)` (the inheriting contract is responsible for that). The output
    ///         token is taken to `address(this)` for the same reason.
    /// @return amountOut The output token amount delivered to this contract.
    function _swapV4ExactIn(
        PoolKey memory key,
        bool zeroForOne,
        uint128 amountIn
    ) internal returns (uint128 amountOut) {
        V4SwapCtx memory ctx = V4SwapCtx({
            key: key,
            zeroForOne: zeroForOne,
            amountSpecified: -int256(uint256(amountIn))
        });
        bytes memory ret = POOL_MANAGER.unlock(abi.encode(ctx));
        BalanceDelta delta = abi.decode(ret, (BalanceDelta));

        // Exact-input: input delta is negative, output is positive.
        int128 outDelta = zeroForOne ? delta.amount1() : delta.amount0();
        amountOut = uint128(int128(outDelta));
    }

    /// @inheritdoc IUnlockCallback
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(POOL_MANAGER)) revert V4DirectNotPoolManager();

        V4SwapCtx memory ctx = abi.decode(data, (V4SwapCtx));

        BalanceDelta delta = POOL_MANAGER.swap(
            ctx.key,
            IPoolManager.SwapParams({
                zeroForOne: ctx.zeroForOne,
                amountSpecified: ctx.amountSpecified,
                sqrtPriceLimitX96: ctx.zeroForOne ? MIN_SQRT_PRICE_PLUS_ONE : MAX_SQRT_PRICE_MINUS_ONE
            }),
            ""
        );

        // Settle input side (we owe tokens to the pool).
        Currency inputCurrency  = ctx.zeroForOne ? ctx.key.currency0 : ctx.key.currency1;
        Currency outputCurrency = ctx.zeroForOne ? ctx.key.currency1 : ctx.key.currency0;
        int128 inputDelta  = ctx.zeroForOne ? delta.amount0() : delta.amount1();
        int128 outputDelta = ctx.zeroForOne ? delta.amount1() : delta.amount0();

        if (inputDelta < 0) {
            uint256 owed = uint256(uint128(-inputDelta));
            if (inputCurrency.isAddressZero()) {
                // Native ETH path. v4-core's PoolManager.settle() comment warns "if settling
                // native, integrators should still call sync first to avoid DoS attack vectors"
                // — that warning addresses external integrators where a prior sync slot might
                // be set by a concurrent caller. We're inside our own unlock callback, the
                // syncedCurrency transient slot is unset (no sync ran in this txn), and
                // PoolManager._settle's address-zero branch takes msg.value directly without
                // consulting reserves. Safe to skip sync here.
                POOL_MANAGER.settle{value: owed}();
            } else {
                POOL_MANAGER.sync(inputCurrency);
                IERC20(Currency.unwrap(inputCurrency)).safeTransfer(address(POOL_MANAGER), owed);
                POOL_MANAGER.settle();
            }
        }

        if (outputDelta > 0) {
            // PoolManager.take() routes native ETH via raw call; the inheriting contract must
            // expose a payable receive() to accept it. SwapRouter and FeeHarvester do — TFLOBuyback
            // does not, and intentionally so: its output side is the ERC-20 TFLO (input is native
            // ETH, settled from msg.value), so take() never sends it ETH. Load-bearing invariant:
            // TFLOBuyback must never be reused for a native-ETH-output swap (it would revert here).
            POOL_MANAGER.take(outputCurrency, address(this), uint256(uint128(outputDelta)));
        }

        return abi.encode(delta);
    }

    // sqrtPriceLimit constants — values from TickMath.MIN_SQRT_PRICE + 1 / MAX_SQRT_PRICE - 1.
    // Inlined to avoid pulling in v4-core's TickMath (large library).
    uint160 internal constant MIN_SQRT_PRICE_PLUS_ONE = 4295128740;
    uint160 internal constant MAX_SQRT_PRICE_MINUS_ONE = 1461446703485210103287273052203988822378723970341;
}
