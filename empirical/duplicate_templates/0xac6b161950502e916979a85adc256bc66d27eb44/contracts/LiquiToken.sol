// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract UncleDegen is ERC20 {
    constructor() ERC20(unicode"Uncle Degen", unicode"$UDG")
    {
        _mint(_msgSender(), 57000000000 * 10 ** decimals());
    }
} 