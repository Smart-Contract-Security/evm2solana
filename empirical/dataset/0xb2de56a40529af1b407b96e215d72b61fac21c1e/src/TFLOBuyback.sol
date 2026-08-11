// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {V4Direct} from "./V4Direct.sol";

/// @title TFLOBuyback
/// @notice Permissionless ETH → TFLO buyback + burn against the V4 TFLO/native-ETH pool. Anyone
///         may call to donate ETH; the caller supplies `minOut` to bound slippage. Called by
///         `Treasury.executeSell` as the final hop of every sell.
///
///         Implementation: runs an exact-input single-hop V4 swap native-ETH → TFLO by calling
///         `PoolManager.unlock` directly (inherited from `V4Direct`), which settles the native
///         input from `msg.value`. The output TFLO is delivered to this contract and burned.
contract TFLOBuyback is V4Direct, ReentrancyGuard {
    ERC20Burnable public immutable TFLO;

    // TFLO/native-ETH PoolKey decomposed for immutable storage (structs cannot be immutable in 0.8.28).
    address public immutable POOL_CURRENCY0;
    address public immutable POOL_CURRENCY1;
    uint24  public immutable POOL_FEE;
    int24   public immutable POOL_TICK_SPACING;
    address public immutable POOL_HOOKS;
    /// @dev Direction of the swap for the buyback: native ETH is the input. Native ETH
    ///      (address(0)) always sorts first, so it is currency0 and zeroForOne is true.
    bool    public immutable ZERO_FOR_ONE;

    error EmptyEth();
    error AmountOverflow();
    error InsufficientOutput(uint128 received, uint128 minOut);

    event Burned(uint256 amount);

    /// @param poolManager     Uniswap V4 PoolManager (mainnet `0x000000000004444c5dc75cB358380D2e3dE08A90`).
    /// @param tflo            TokenFlow token (must support `burn`).
    /// @param poolKey         The TFLO/native-ETH V4 PoolKey set at launch.
    constructor(
        IPoolManager poolManager,
        address tflo,
        PoolKey memory poolKey
    ) V4Direct(poolManager) {
        TFLO              = ERC20Burnable(tflo);

        POOL_CURRENCY0    = Currency.unwrap(poolKey.currency0);
        POOL_CURRENCY1    = Currency.unwrap(poolKey.currency1);
        POOL_FEE          = poolKey.fee;
        POOL_TICK_SPACING = poolKey.tickSpacing;
        POOL_HOOKS        = address(poolKey.hooks);

        // Buyback direction: native ETH → TFLO. zeroForOne ⇔ native ETH is currency0.
        ZERO_FOR_ONE      = (POOL_CURRENCY0 == address(0));
    }

    /// @notice Swap `msg.value` ETH → TFLO via the V4 TFLO/native-ETH pool, then burn the proceeds.
    /// @param minOut Minimum acceptable TFLO output. Caller is responsible for this value.
    function buyAndBurn(uint128 minOut) external payable nonReentrant {
        if (msg.value == 0) revert EmptyEth();
        if (msg.value > type(uint128).max) revert AmountOverflow();
        uint128 amountIn = uint128(msg.value);

        // V4Direct's unlockCallback settles the native input from this contract's balance
        // (msg.value) via PoolManager.settle{value:}.
        uint128 received = _swapV4ExactIn(_key(), ZERO_FOR_ONE, amountIn);
        if (received < minOut) revert InsufficientOutput(received, minOut);

        TFLO.burn(received);
        emit Burned(received);
    }

    function _key() internal view returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(POOL_CURRENCY0),
            currency1: Currency.wrap(POOL_CURRENCY1),
            fee: POOL_FEE,
            tickSpacing: POOL_TICK_SPACING,
            hooks: IHooks(POOL_HOOKS)
        });
    }
}
