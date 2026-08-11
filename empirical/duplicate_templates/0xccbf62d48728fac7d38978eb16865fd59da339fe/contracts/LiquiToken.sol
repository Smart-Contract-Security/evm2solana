// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract GrizzCapital is ERC20 {
    constructor() ERC20(unicode"GrizzCapital", unicode"🐻GZC")
    {
        _mint(_msgSender(), 11000000000 * 10 ** decimals());
    }
} 