// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CopperToad is ERC20 {
    constructor() ERC20(unicode"Copper Toad", unicode"🐸CPT")
    {
        _mint(_msgSender(), 36000000000 * 10 ** decimals());
    }
} 