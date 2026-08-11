// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract GhostLiquidityERC20 is ERC20 {
    constructor() ERC20(unicode"Ghost Liquidity", unicode"👻GHLQ")
    {
        _mint(_msgSender(), 77000000000 * 10 ** decimals());
    }
} 