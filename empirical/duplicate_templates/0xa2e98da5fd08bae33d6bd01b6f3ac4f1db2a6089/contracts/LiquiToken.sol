// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract SSonyc is ERC20 {
    constructor() ERC20(unicode"Second Sonyc", unicode"SSONYC")
    {
        _mint(_msgSender(), 55000000000 * 10 ** decimals());
    }
} 