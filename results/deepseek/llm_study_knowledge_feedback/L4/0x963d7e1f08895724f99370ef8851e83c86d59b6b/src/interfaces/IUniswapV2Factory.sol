// SPDX-License-Identifier: MIT

import 'solana';

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB, address pair, address programId) external returns (address);

    function getPair(address tokenA, address tokenB, address programId) external view returns (address);
}