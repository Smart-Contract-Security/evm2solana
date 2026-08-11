// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BackAlleySwap is ERC20 {
    constructor() ERC20(unicode"Back Alley Swap", unicode"BAS")
    {
        _mint(_msgSender(), 84000000000 * 10 ** decimals());
    }
} 