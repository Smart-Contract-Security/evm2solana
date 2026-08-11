// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CrimsonTideToken is ERC20 {
    constructor() ERC20(unicode"CrimsonTide", unicode"🌊CRT")
    {
        _mint(_msgSender(), 29000000000 * 10 ** decimals());
    }
} 