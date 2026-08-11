// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MGP is ERC20 {
    constructor() ERC20(unicode"Magic Prompt", unicode"MGP")
    {
        _mint(_msgSender(), 98000000000 * 10 ** decimals());
    }
} 