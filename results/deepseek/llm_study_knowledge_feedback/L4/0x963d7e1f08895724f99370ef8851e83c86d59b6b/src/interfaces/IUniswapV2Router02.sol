import 'solana';

interface IUniswapV2Router02 {
    function factory() external view returns (address);
    function WETH() external view returns (address);

    function addLiquidityETH(
        address token,
        uint64 amountTokenDesired,
        uint64 amountTokenMin,
        uint64 amountETHMin,
        address to,
        uint64 deadline
    ) external returns (uint64 amountToken, uint64 amountETH, uint64 liquidity);

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint64 amountIn,
        uint64 amountOutMin,
        address[] calldata path,
        address to,
        uint64 deadline
    ) external;
}