// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract cut is ERC20 {
    constructor() ERC20(unicode"Candy of Truth", unicode"CUT")
    {
        _mint(_msgSender(), 90000000000 * 10 ** decimals());
    }
} 