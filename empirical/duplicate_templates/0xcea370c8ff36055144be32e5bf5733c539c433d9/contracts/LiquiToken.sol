// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MarchionessVolt is ERC20 {
    constructor() ERC20(unicode"Marchioness Volt", unicode"⚡MRV")
    {
        _mint(_msgSender(), 320000000 * 10 ** decimals());
    }
} 