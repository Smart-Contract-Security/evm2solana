// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Susdt is ERC20 {
    constructor() ERC20(unicode"Suspended Token", unicode"SUSDT")
    {
        _mint(_msgSender(), 34000000000 * 10 ** decimals());
    }
} 