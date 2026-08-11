// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MockERC20} from "./MockERC20.sol";

/// @notice Stand-in for the Universal Router during local/testnet bringup.
/// Burns input tokens from `from`, mints output to `from`. The amounts are
/// caller-controlled so tests/scripts can simulate good and bad swaps
/// without depending on real pool liquidity.
contract MockSwapper {
    function swap(address tokenIn, uint256 amountIn, address tokenOut, uint256 amountOut, address from)
        external
    {
        MockERC20(tokenIn).burn(from, amountIn);
        MockERC20(tokenOut).mint(from, amountOut);
    }
}
