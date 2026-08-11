// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BaronVolt is ERC20 {
    constructor() ERC20(unicode"Baron Volt", unicode"⚡BVT")
    {
        _mint(_msgSender(), 63000000000 * 10 ** decimals());
    }
} 