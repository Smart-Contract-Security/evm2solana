// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract GildedFrog is ERC20 {
    constructor() ERC20(unicode"Gilded Frog", unicode"🐸$GLF")
    {
        _mint(_msgSender(), 25000000000 * 10 ** decimals());
    }
} 