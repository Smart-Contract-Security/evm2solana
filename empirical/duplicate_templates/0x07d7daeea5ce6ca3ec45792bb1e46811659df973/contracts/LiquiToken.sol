// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ZPatriot is ERC20 {
    constructor() ERC20(unicode"Z Patriot", unicode"ZPATRIOT")
    {
        _mint(_msgSender(), 66000000000 * 10 ** decimals());
    }
} 