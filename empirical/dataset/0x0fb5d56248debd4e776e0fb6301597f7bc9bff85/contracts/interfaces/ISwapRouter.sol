// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

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
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut);
}
