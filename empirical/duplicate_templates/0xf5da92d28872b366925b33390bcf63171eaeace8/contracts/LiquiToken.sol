// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Shit is ERC20 {
    constructor() ERC20(unicode"Shiba Tutorial", unicode"SHIT")
    {
        _mint(_msgSender(), 68000000000 * 10 ** decimals());
    }
} 