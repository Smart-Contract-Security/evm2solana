// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract GoblinModeToken is ERC20 {
    constructor() ERC20(unicode"Goblin Mode", unicode"🎲GBM")
    {
        _mint(_msgSender(), 76000000000 * 10 ** decimals());
    }
} 