// SPDX-License-Identifier: MIT

import 'solana';

/// @notice Minimal Uniswap V3 SwapRouter02 interface (exactInput only).
///
/// `path` is a packed V3 route: tokenIn (20) || fee (3) || ... || tokenOut (20).
/// For a direct A->HOUSE swap with the 0.3% pool that's 43 bytes:
///   abi.encodePacked(A, uint24(3000), HOUSE)
/// For a hop A->USDC->HOUSE it's 66 bytes:
///   abi.encodePacked(A, uint24(100), USDC, uint24(3000), HOUSE)
interface ISwapRouter {
    struct ExactInputParams {
        bytes path;
        address recipient;
        uint64 amountIn;
        uint64 amountOutMinimum;
    }

    function exactInput(ExactInputParams calldata params) external returns (uint64 amountOut);
}