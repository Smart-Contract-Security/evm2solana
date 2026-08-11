// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MadamYieldToken is ERC20 {
    constructor() ERC20(unicode"Madam Yield", unicode"💎MDY")
    {
        _mint(_msgSender(), 55000000000 * 10 ** decimals());
    }
} 