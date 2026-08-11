// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {LiquidityAmounts} from "v4-periphery/src/libraries/LiquidityAmounts.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";

interface IAllowanceTransfer {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}

/// @notice Single-side V4 liquidity seeder. Assumes pool was already initialized at startTick.
/// If fortIsToken0 is false (ETH/FORT pair, standard case), position is [MIN_aligned, startTick]
/// and currentTick must equal startTick (so the position is purely token1 = FORT).
/// If fortIsToken0 is true, position is [startTick, MAX_aligned] and currentTick must equal startTick.
contract LpManager {
    error NotOwner();
    error AlreadySeeded();

    address public immutable owner;
    IERC20 public immutable fort;
    IPoolManager public immutable poolManager;
    IPositionManager public immutable positionManager;
    IAllowanceTransfer public immutable permit2;
    bool public immutable fortIsToken0;
    int24 public immutable startTick;
    int24 public immutable tickLower;
    int24 public immutable tickUpper;
    PoolKey public poolKey;
    bool public seeded;
    uint256 public tokenId;

    int24 public constant TICK_SPACING = 200;
    // MAX_TICK for v4 is 887272; nearest multiple-of-200 ≤ that is 887200.
    int24 public constant MAX_TICK_ALIGNED = 887200;
    int24 public constant MIN_TICK_ALIGNED = -887200;

    constructor(
        address owner_,
        address fort_,
        address poolManager_,
        address positionManager_,
        address permit2_,
        PoolKey memory poolKey_,
        bool fortIsToken0_,
        int24 startTick_
    ) {
        owner = owner_;
        fort = IERC20(fort_);
        poolManager = IPoolManager(poolManager_);
        positionManager = IPositionManager(positionManager_);
        permit2 = IAllowanceTransfer(permit2_);
        poolKey = poolKey_;
        fortIsToken0 = fortIsToken0_;
        startTick = startTick_;

        if (fortIsToken0_) {
            tickLower = startTick_;
            tickUpper = MAX_TICK_ALIGNED;
        } else {
            tickLower = MIN_TICK_ALIGNED;
            tickUpper = startTick_;
        }
    }

    function seed() external {
        if (msg.sender != owner) revert NotOwner();
        if (seeded) revert AlreadySeeded();
        seeded = true;

        uint256 amount = fort.balanceOf(address(this));

        // two-step Permit2 approval (lesson v4_lp_via_permit2)
        fort.approve(address(permit2), type(uint256).max);
        permit2.approve(address(fort), address(positionManager), type(uint160).max, type(uint48).max);

        uint160 sqrtLower = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtUpper = TickMath.getSqrtPriceAtTick(tickUpper);
        uint128 liquidity = fortIsToken0
            ? LiquidityAmounts.getLiquidityForAmount0(sqrtLower, sqrtUpper, amount)
            : LiquidityAmounts.getLiquidityForAmount1(sqrtLower, sqrtUpper, amount);

        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR));
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(
            poolKey,
            tickLower,
            tickUpper,
            uint256(liquidity),
            uint128(amount),  // amount0Max
            uint128(amount),  // amount1Max — upper bound, only one side actually consumed
            owner,
            bytes("")
        );
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1);

        tokenId = positionManager.nextTokenId();
        positionManager.modifyLiquidities(abi.encode(actions, params), block.timestamp + 600);
    }
}
