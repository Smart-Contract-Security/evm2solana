// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract GigaSeasonERC20 is ERC20 {
    constructor() ERC20(unicode"Giga Season", unicode"🌈GGS")
    {
        _mint(_msgSender(), 95000000000 * 10 ** decimals());
    }
} 