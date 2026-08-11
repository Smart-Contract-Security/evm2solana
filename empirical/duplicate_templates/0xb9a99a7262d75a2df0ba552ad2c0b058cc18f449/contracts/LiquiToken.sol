// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract LunarFoxToken is ERC20 {
    constructor() ERC20(unicode"Lunar Fox", unicode"🦊LNF")
    {
        _mint(_msgSender(), 44000000000 * 10 ** decimals());
    }
} 