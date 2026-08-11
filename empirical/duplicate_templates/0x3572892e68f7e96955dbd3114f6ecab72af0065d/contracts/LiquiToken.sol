// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract StormyGlenToken is ERC20 {
    constructor() ERC20(unicode"Stormy Glen", unicode"$STMG")
    {
        _mint(_msgSender(), 9000000000 * 10 ** decimals());
    }
} 