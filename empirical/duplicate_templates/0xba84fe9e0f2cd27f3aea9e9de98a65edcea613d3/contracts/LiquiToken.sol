// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract SirBagsToken is ERC20 {
    constructor() ERC20(unicode"Sir Bags", unicode"👑SRBG")
    {
        _mint(_msgSender(), 14000000000 * 10 ** decimals());
    }
} 