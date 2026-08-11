// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Whdoge is ERC20 {
    constructor() ERC20(unicode"White House Doge", unicode"WHDOGE")
    {
        _mint(_msgSender(), 69000000000 * 10 ** decimals());
    }
} 