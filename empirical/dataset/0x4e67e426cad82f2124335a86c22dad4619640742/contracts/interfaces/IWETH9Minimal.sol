// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20Minimal} from "@uniswap/v4-core/src/interfaces/external/IERC20Minimal.sol";

/// @notice Minimal WETH9 surface for wrapping presale ETH before v4 liquidity settlement.
interface IWETH9Minimal is IERC20Minimal {
    function deposit() external payable;
}
