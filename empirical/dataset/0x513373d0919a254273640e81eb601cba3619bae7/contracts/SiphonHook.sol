// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {
    BeforeSwapDelta,
    toBeforeSwapDelta,
    BeforeSwapDeltaLibrary
} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";

interface ISiphon {
    function distribute(uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
}

/// @title SiphonHook
/// @notice Uniswap V4 hook for SIPHON:
///         • 10% sell tax (SIPHON → other): take fee, flush whole hook pot to holders.
///         • 10% buy tax (other → SIPHON): take fee, accrue in hook (no distribute call).
///         • All redistribution gas is paid by the seller.
///         Gating: until `enableTrading()` is called by the setup contract, the hook
///         rejects swaps and rejects pool init / liquidity adds from anyone other
///         than the setup contract. This makes frontrunning the launch impossible.
contract SiphonHook is BaseHook {
    using BeforeSwapDeltaLibrary for BeforeSwapDelta;

    uint256 private constant TAX_NUM = 1000; // 10%
    uint256 private constant TAX_DEN = 10000;

    ISiphon public immutable siphon;
    Currency public immutable siphonCurrency;
    address public immutable setupContract;

    bool public tradingEnabled;

    event BuyTaxAccrued(uint256 fee);
    event SellTaxFlushed(uint256 fee, uint256 totalDistributed);
    event TradingEnabled();

    error OnlyExactInput();
    error PoolMustContainSiphon();
    error TradingNotEnabled();
    error LaunchGated();
    error NotSetup();

    constructor(IPoolManager _poolManager, address _siphon, address _setup) BaseHook(_poolManager) {
        siphon = ISiphon(_siphon);
        siphonCurrency = Currency.wrap(_siphon);
        setupContract = _setup;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: false,
            beforeAddLiquidity: true,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: true,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /// @notice Flip to allow public trading and public liquidity. One-way.
    function enableTrading() external {
        if (msg.sender != setupContract) revert NotSetup();
        tradingEnabled = true;
        emit TradingEnabled();
    }

    /// @notice Anyone can call to flush accumulated buy tax to holders.
    ///         The seller would normally trigger this on their sell, but exposing
    ///         it lets a holder pay gas to compound their own dividends if no
    ///         sells have happened in a while.
    function flush() external {
        if (!tradingEnabled) revert TradingNotEnabled();
        uint256 pot = siphon.balanceOf(address(this));
        if (pot != 0) siphon.distribute(pot);
    }

    // ─────────────────────────── HOOK CALLBACKS ───────────────────────────

    function _beforeInitialize(address sender, PoolKey calldata key, uint160)
        internal
        view
        override
        returns (bytes4)
    {
        // Only the setup contract can initialize the canonical SIPHON pool.
        // Prevents a frontrunner from anchoring the pool at a malicious price.
        if (sender != setupContract) revert NotSetup();
        if (
            Currency.unwrap(key.currency0) != Currency.unwrap(siphonCurrency) &&
            Currency.unwrap(key.currency1) != Currency.unwrap(siphonCurrency)
        ) revert PoolMustContainSiphon();
        return BaseHook.beforeInitialize.selector;
    }

    function _beforeAddLiquidity(
        address sender,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        bytes calldata
    ) internal view override returns (bytes4) {
        // Before trading is enabled, only setup can add LP. Stops a frontrunner
        // from seeding the pool with adversarial liquidity at a bad price.
        if (!tradingEnabled && sender != setupContract) revert LaunchGated();
        return BaseHook.beforeAddLiquidity.selector;
    }

    function _beforeSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        if (!tradingEnabled) revert TradingNotEnabled();
        if (params.amountSpecified > 0) revert OnlyExactInput();

        (, bool sellingSiphon) = _swapSides(key, params.zeroForOne);
        if (!sellingSiphon) {
            // Buy: fee taken in afterSwap (output amount unknown until swap math runs).
            return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }

        // SELL: take 10% of SIPHON input, then flush the entire hook pot.
        uint256 inputAmount = uint256(-params.amountSpecified);
        uint256 fee;
        unchecked { fee = (inputAmount * TAX_NUM) / TAX_DEN; }

        if (fee != 0) {
            poolManager.take(siphonCurrency, address(this), fee);
        }

        uint256 pot = siphon.balanceOf(address(this));
        if (pot != 0) siphon.distribute(pot);

        emit SellTaxFlushed(fee, pot);

        // +specifiedDelta = hook claims `fee` of the specified (input) currency.
        return (BaseHook.beforeSwap.selector, toBeforeSwapDelta(int128(int256(fee)), int128(0)), 0);
    }

    function _afterSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) internal override returns (bytes4, int128) {
        (bool siphonIsCurrency0, bool sellingSiphon) = _swapSides(key, params.zeroForOne);
        if (sellingSiphon) return (BaseHook.afterSwap.selector, int128(0));

        // BUY: SIPHON is output (unspecified). Take 10% of the swap's SIPHON output and accrue.
        int128 siphonOut = siphonIsCurrency0 ? delta.amount0() : delta.amount1();
        if (siphonOut <= 0) return (BaseHook.afterSwap.selector, int128(0));

        uint256 outAbs = uint256(int256(siphonOut));
        uint256 fee;
        unchecked { fee = (outAbs * TAX_NUM) / TAX_DEN; }
        if (fee == 0) return (BaseHook.afterSwap.selector, int128(0));

        poolManager.take(siphonCurrency, address(this), fee);
        emit BuyTaxAccrued(fee);

        // +unspecifiedDelta = hook took `fee` of the unspecified (output) currency.
        return (BaseHook.afterSwap.selector, int128(int256(fee)));
    }

    // ─────────────────────────── INTERNAL HELPERS ───────────────────────────

    function _swapSides(PoolKey calldata key, bool zeroForOne)
        internal
        view
        returns (bool siphonIsCurrency0, bool sellingSiphon)
    {
        address s = Currency.unwrap(siphonCurrency);
        address c0 = Currency.unwrap(key.currency0);
        address c1 = Currency.unwrap(key.currency1);
        if (c0 == s) {
            siphonIsCurrency0 = true;
        } else if (c1 != s) {
            revert PoolMustContainSiphon();
        }
        // Input is SIPHON when: (SIPHON=cur0 && zeroForOne) || (SIPHON=cur1 && !zeroForOne)
        sellingSiphon = siphonIsCurrency0 == zeroForOne;
    }
}
