// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BTWO is ERC20 {
    constructor() ERC20(unicode"BTwo", unicode"B2")
    {
        _mint(_msgSender(), 99000000000 * 10 ** decimals());
    }
} 