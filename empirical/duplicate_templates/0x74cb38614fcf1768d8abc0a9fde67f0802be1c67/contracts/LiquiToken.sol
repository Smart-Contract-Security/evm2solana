// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract grumm is ERC20 {
    constructor() ERC20(unicode"Grumm", unicode"GRUMM")
    {
        _mint(_msgSender(), 4000000000 * 10 ** decimals());
    }
} 