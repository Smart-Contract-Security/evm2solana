// SPDX-License-Identifier: MIT

import 'solana';

/// @notice Thin forwarder around Uniswap's Universal Router. The off-chain router
///         (backend `services/routing`) computes the full `(commands, inputs)` —
///         spanning V2/V3/V4 and any stablecoin/WETH intermediaries — and the
///         contract enforces `minOut` via a balance-delta check on the caller.
interface ISwapRouter {
    function swapExactEthForToken(
        address tokenOut,
        bytes calldata commands,
        bytes[] calldata inputs,
        uint64 minOut
    ) external returns (uint64 out);

    function swapExactTokenForEth(
        address tokenIn,
        uint64 amountIn,
        bytes calldata commands,
        bytes[] calldata inputs,
        uint64 minOut
    ) external returns (uint64 ethOut);
}