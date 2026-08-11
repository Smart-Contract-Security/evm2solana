// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Chsp is ERC20 {
    constructor() ERC20(unicode"Chicken Swap", unicode"CSWAP")
    {
        _mint(_msgSender(), 7000000000 * 10 ** decimals());
    }
} 