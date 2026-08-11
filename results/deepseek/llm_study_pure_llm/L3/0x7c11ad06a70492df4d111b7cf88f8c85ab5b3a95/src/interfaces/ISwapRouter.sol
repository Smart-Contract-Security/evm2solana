// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Thin forwarder around Uniswap's Universal Router. The off-chain router
///         (backend `services/routing`) computes the full `(commands, inputs)` —
///         spanning V2/V3/V4 and any stablecoin/WETH intermediaries — and the
///         contract enforces `minOut` via a balance-delta check on the caller.
interface ISwapRouter {
    function swapExactEthForToken(
        address tokenOut,
        bytes calldata commands,
        bytes[] calldata inputs,
        uint256 minOut
    ) external payable returns (uint256 out);

    function swapExactTokenForEth(
        address tokenIn,
        uint256 amountIn,
        bytes calldata commands,
        bytes[] calldata inputs,
        uint256 minOut
    ) external returns (uint256 ethOut);
}