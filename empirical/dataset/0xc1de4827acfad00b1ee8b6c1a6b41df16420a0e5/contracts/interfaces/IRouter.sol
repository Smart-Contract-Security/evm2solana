// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IFeeCalculator} from "./IFeeCalculator.sol";

interface IRouter {
    function quoteExactInput(address assetIn, address assetOut, uint256 amountIn)
        external
        view
        returns (IFeeCalculator.FeeBreakdown memory);

    function swapExactInput(
        address assetIn,
        address assetOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address receiver
    ) external returns (uint256 amountOut, uint256 feeAmount);

    event Swap(
        address indexed assetIn,
        address indexed assetOut,
        address indexed sender,
        address receiver,
        uint256 amountIn,
        uint256 amountOut,
        uint256 fee
    );
}
