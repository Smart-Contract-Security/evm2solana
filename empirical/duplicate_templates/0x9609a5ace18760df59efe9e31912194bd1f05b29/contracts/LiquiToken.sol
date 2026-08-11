// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract SaltyMike is ERC20 {
    constructor() ERC20(unicode"Salty Mike", unicode"SMK")
    {
        _mint(_msgSender(), 13000000000 * 10 ** decimals());
    }
} 