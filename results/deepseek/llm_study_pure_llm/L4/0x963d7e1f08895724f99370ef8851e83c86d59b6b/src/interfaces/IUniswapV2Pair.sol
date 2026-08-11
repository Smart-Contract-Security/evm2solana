// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import 'solana';

interface IUniswapV2Pair {
    function skim(address to) external;
}