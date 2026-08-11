// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DizzyBagsToken is ERC20 {
    constructor() ERC20(unicode"Dizzy Bags", unicode"💫DZB")
    {
        _mint(_msgSender(), 56000000000 * 10 ** decimals());
    }
} 