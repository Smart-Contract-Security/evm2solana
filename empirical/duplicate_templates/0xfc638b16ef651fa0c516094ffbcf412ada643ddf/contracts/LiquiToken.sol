// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DarkForestToken is ERC20 {
    constructor() ERC20(unicode"Dark Forest", unicode"🌲DKF")
    {
        _mint(_msgSender(), 67000000000 * 10 ** decimals());
    }
} 