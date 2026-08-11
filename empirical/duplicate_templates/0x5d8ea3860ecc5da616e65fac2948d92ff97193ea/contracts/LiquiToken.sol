// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TNT is ERC20 {
    constructor() ERC20(unicode"Trump & Truth", unicode"T&T")
    {
        _mint(_msgSender(), 46000000000 * 10 ** decimals());
    }
} 