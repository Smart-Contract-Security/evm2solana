// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ExitLiquidityToken is ERC20 {
    constructor() ERC20(unicode"Exit Liquidity", unicode"$XLQ")
    {
        _mint(_msgSender(), 50000000000 * 10 ** decimals());
    }
} 