// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BuyTheDip is ERC20 {
    constructor() ERC20(unicode"Buy The Dip", unicode"💫BTD")
    {
        _mint(_msgSender(), 73000000000 * 10 ** decimals());
    }
} 