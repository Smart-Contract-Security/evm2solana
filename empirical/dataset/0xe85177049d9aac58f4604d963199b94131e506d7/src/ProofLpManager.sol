// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IUnlockCallback}        from "v4-core/interfaces/callback/IUnlockCallback.sol";
import {IPoolManager}           from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey}                from "v4-core/types/PoolKey.sol";
import {Currency}               from "v4-core/types/Currency.sol";
import {BalanceDelta}           from "v4-core/types/BalanceDelta.sol";
import {TickMath}               from "v4-core/libraries/TickMath.sol";
import {FullMath}               from "v4-core/libraries/FullMath.sol";
import {StateLibrary}           from "v4-core/libraries/StateLibrary.sol";
import {PoolIdLibrary}          from "v4-core/types/PoolId.sol";
import {IERC20Minimal}          from "v4-core/interfaces/external/IERC20Minimal.sol";

/// @title ProofLpManager — owner-only LP position manager for the $PROOF pool.
/// @dev Same pattern as BaseStation / BaseStar — single-position manager,
///      out-of-range single-side LP support via sqrtPrice branching.
contract ProofLpManager is IUnlockCallback {
    using StateLibrary  for IPoolManager;
    using PoolIdLibrary for PoolKey;

    IPoolManager public immutable pm;
    address      public immutable owner;

    uint256 private constant Q96 = 0x1000000000000000000000000;

    enum Action { ADD, REMOVE, CLAIM }

    struct CallbackData {
        Action  action;
        PoolKey key;
        int24   tickLower;
        int24   tickUpper;
        uint256 amount0;
        uint256 amount1;
        uint128 liquidity;
        address token1;
    }

    constructor(address _pm, address _owner) {
        pm    = IPoolManager(_pm);
        owner = _owner;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "only owner");
        _;
    }

    function positionLiquidity(PoolKey calldata key, int24 tickLower, int24 tickUpper)
        external view returns (uint128 liquidity)
    {
        (liquidity,,) = pm.getPositionInfo(key.toId(), address(this), tickLower, tickUpper, bytes32(0));
    }

    function addLiquidity(
        PoolKey  calldata key,
        int24    tickLower,
        int24    tickUpper,
        uint256  amount1
    ) external payable onlyOwner {
        address token1 = Currency.unwrap(key.currency1);
        if (amount1 > 0) {
            IERC20Minimal(token1).transferFrom(msg.sender, address(this), amount1);
        }

        pm.unlock(abi.encode(CallbackData({
            action:    Action.ADD,
            key:       key,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0:   msg.value,
            amount1:   amount1,
            liquidity: 0,
            token1:    token1
        })));

        _refund(token1);
    }

    function removeLiquidity(
        PoolKey  calldata key,
        int24    tickLower,
        int24    tickUpper,
        uint128  liquidity
    ) external onlyOwner {
        if (liquidity == 0) {
            (liquidity,,) = pm.getPositionInfo(key.toId(), address(this), tickLower, tickUpper, bytes32(0));
            require(liquidity > 0, "no liquidity");
        }

        address token1 = Currency.unwrap(key.currency1);
        pm.unlock(abi.encode(CallbackData({
            action:    Action.REMOVE,
            key:       key,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0:   0,
            amount1:   0,
            liquidity: liquidity,
            token1:    token1
        })));
    }

    function claimFees(
        PoolKey  calldata key,
        int24    tickLower,
        int24    tickUpper
    ) external onlyOwner {
        address token1 = Currency.unwrap(key.currency1);
        pm.unlock(abi.encode(CallbackData({
            action:    Action.CLAIM,
            key:       key,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0:   0,
            amount1:   0,
            liquidity: 0,
            token1:    token1
        })));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(pm), "not pm");
        CallbackData memory d = abi.decode(data, (CallbackData));

        if      (d.action == Action.ADD)    _handleAdd(d);
        else if (d.action == Action.REMOVE) _handleRemove(d);
        else                                _handleClaim(d);

        return "";
    }

    function _handleAdd(CallbackData memory d) internal {
        (uint160 sqrtPriceX96,,,) = pm.getSlot0(d.key.toId());
        require(sqrtPriceX96 > 0, "pool not initialized");

        uint160 sqrtLower = TickMath.getSqrtPriceAtTick(d.tickLower);
        uint160 sqrtUpper = TickMath.getSqrtPriceAtTick(d.tickUpper);

        uint128 liquidity;
        if (sqrtPriceX96 <= sqrtLower) {
            require(d.amount0 > 0, "need amount0");
            liquidity = _liquidityForAmount0(sqrtLower, sqrtUpper, d.amount0);
        } else if (sqrtPriceX96 >= sqrtUpper) {
            require(d.amount1 > 0, "need amount1");
            liquidity = _liquidityForAmount1(sqrtLower, sqrtUpper, d.amount1);
        } else {
            uint128 liq0 = _liquidityForAmount0(sqrtPriceX96, sqrtUpper, d.amount0);
            uint128 liq1 = _liquidityForAmount1(sqrtLower, sqrtPriceX96, d.amount1);
            liquidity = liq0 < liq1 ? liq0 : liq1;
        }
        require(liquidity > 0, "zero liquidity");

        (BalanceDelta cd,) = pm.modifyLiquidity(
            d.key,
            IPoolManager.ModifyLiquidityParams({
                tickLower:      d.tickLower,
                tickUpper:      d.tickUpper,
                liquidityDelta: int256(uint256(liquidity)),
                salt:           bytes32(0)
            }),
            ""
        );

        int128 d0 = cd.amount0();
        if (d0 < 0) pm.settle{value: uint128(-d0)}();
        else if (d0 > 0) pm.take(d.key.currency0, owner, uint128(d0));

        int128 d1 = cd.amount1();
        if (d1 < 0) {
            uint128 owed = uint128(-d1);
            pm.sync(d.key.currency1);
            IERC20Minimal(d.token1).transfer(address(pm), owed);
            pm.settle();
        } else if (d1 > 0) {
            pm.take(d.key.currency1, owner, uint128(d1));
        }
    }

    function _handleRemove(CallbackData memory d) internal {
        (BalanceDelta cd,) = pm.modifyLiquidity(
            d.key,
            IPoolManager.ModifyLiquidityParams({
                tickLower:      d.tickLower,
                tickUpper:      d.tickUpper,
                liquidityDelta: -int256(uint256(d.liquidity)),
                salt:           bytes32(0)
            }),
            ""
        );

        int128 d0 = cd.amount0();
        if (d0 > 0) pm.take(d.key.currency0, owner, uint128(d0));

        int128 d1 = cd.amount1();
        if (d1 > 0) pm.take(d.key.currency1, owner, uint128(d1));
    }

    function _handleClaim(CallbackData memory d) internal {
        (BalanceDelta cd,) = pm.modifyLiquidity(
            d.key,
            IPoolManager.ModifyLiquidityParams({
                tickLower:      d.tickLower,
                tickUpper:      d.tickUpper,
                liquidityDelta: 0,
                salt:           bytes32(0)
            }),
            ""
        );

        int128 d0 = cd.amount0();
        if (d0 > 0) pm.take(d.key.currency0, owner, uint128(d0));

        int128 d1 = cd.amount1();
        if (d1 > 0) pm.take(d.key.currency1, owner, uint128(d1));
    }

    function _refund(address token1) internal {
        uint256 ethLeft = address(this).balance;
        if (ethLeft > 0) payable(owner).transfer(ethLeft);
        uint256 tokLeft = IERC20Minimal(token1).balanceOf(address(this));
        if (tokLeft > 0) IERC20Minimal(token1).transfer(owner, tokLeft);
    }

    function _liquidityForAmount0(uint160 sqrtA, uint160 sqrtB, uint256 amount0) private pure returns (uint128) {
        if (sqrtA > sqrtB) (sqrtA, sqrtB) = (sqrtB, sqrtA);
        uint256 inter = FullMath.mulDiv(sqrtA, sqrtB, Q96);
        return uint128(FullMath.mulDiv(amount0, inter, uint256(sqrtB) - uint256(sqrtA)));
    }
    function _liquidityForAmount1(uint160 sqrtA, uint160 sqrtB, uint256 amount1) private pure returns (uint128) {
        if (sqrtA > sqrtB) (sqrtA, sqrtB) = (sqrtB, sqrtA);
        return uint128(FullMath.mulDiv(amount1, Q96, uint256(sqrtB) - uint256(sqrtA)));
    }

    receive() external payable {}
}
