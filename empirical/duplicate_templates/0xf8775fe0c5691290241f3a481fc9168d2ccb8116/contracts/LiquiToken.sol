// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract StormBearERC20 is ERC20 {
    constructor() ERC20(unicode"StormBear", unicode"🐻STB")
    {
        _mint(_msgSender(), 37000000000 * 10 ** decimals());
    }
} 