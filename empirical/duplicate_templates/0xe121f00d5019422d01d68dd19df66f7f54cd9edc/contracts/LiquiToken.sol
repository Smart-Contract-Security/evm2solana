// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CountMoonshot is ERC20 {
    constructor() ERC20(unicode"Count Moonshot", unicode"🌕CMS")
    {
        _mint(_msgSender(), 84000000000 * 10 ** decimals());
    }
} 