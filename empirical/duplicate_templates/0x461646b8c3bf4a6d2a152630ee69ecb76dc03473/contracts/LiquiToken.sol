// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract PraetorVoltToken is ERC20 {
    constructor() ERC20(unicode"Praetor Volt", unicode"⚡PRV")
    {
        _mint(_msgSender(), 81000000000 * 10 ** decimals());
    }
} 