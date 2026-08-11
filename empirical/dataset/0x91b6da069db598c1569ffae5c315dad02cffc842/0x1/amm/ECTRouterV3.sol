// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ECTPoolV3} from "./ECTPoolV3.sol";
import {ECTPoolFactoryV3} from "./ECTPoolFactoryV3.sol";

contract ECTRouterV3 {
    using SafeERC20 for IERC20;

    error Expired();
    error InsufficientOutput();
    error PoolMissing();
    error InvalidPath();

    ECTPoolFactoryV3 public immutable factory;
    address public immutable ect;

    constructor(address _factory, address _ect) {
        factory = ECTPoolFactoryV3(_factory);
        ect = _ect;
    }

    modifier ensure(uint256 deadline) {
        if (deadline < block.timestamp) revert Expired();
        _;
    }

    /// @notice Quote a single-hop swap through the V3 pool at the given tick spacing.
    function getAmountOut(address tokenIn, address tokenOut, int24 tickSpacing, uint256 amountIn)
        public
        view
        returns (uint256 amountOut)
    {
        address nonEct = tokenIn == ect ? tokenOut : tokenIn;
        address pool = factory.getPool(nonEct, tickSpacing);
        if (pool == address(0)) revert PoolMissing();
        (uint256 r0, uint256 r1, ) = ECTPoolV3(pool).getReserves();
        address t0 = ECTPoolV3(pool).token0();
        (uint256 rIn, uint256 rOut) = tokenIn == t0 ? (r0, r1) : (r1, r0);
        if (rIn == 0 || rOut == 0) return 0;

        // Match the pool's swap math: protocol fee + LP fee.
        uint256 afterProtocol = (amountIn * 9900) / 10_000;
        uint256 afterLp = (afterProtocol * 9970) / 10_000;
        amountOut = (afterLp * rOut) / (rIn + afterLp);
    }

    struct SwapParams {
        uint256 amountIn;
        uint256 minOut;
        address tokenIn;
        address tokenOut;
        int24 tickSpacing;
        address to;
        uint256 deadline;
    }

    /// @notice Execute a single-hop swap on the V3 pool at `tickSpacing`.
    function swapExactTokensForTokens(SwapParams calldata p)
        external
        ensure(p.deadline)
        returns (uint256 amountOut)
    {
        address pool = factory.getPool(p.tokenIn == ect ? p.tokenOut : p.tokenIn, p.tickSpacing);
        if (pool == address(0)) revert PoolMissing();
        bool zeroForOne = p.tokenIn == ECTPoolV3(pool).token0();

        IERC20(p.tokenIn).safeTransferFrom(msg.sender, address(this), p.amountIn);
        IERC20(p.tokenIn).approve(pool, p.amountIn);
        amountOut = ECTPoolV3(pool).swap(p.to, zeroForOne, p.amountIn, p.minOut);
        if (amountOut < p.minOut) revert InsufficientOutput();
    }
}
