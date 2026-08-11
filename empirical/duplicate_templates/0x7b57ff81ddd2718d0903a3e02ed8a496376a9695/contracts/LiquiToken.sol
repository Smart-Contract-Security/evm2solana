// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ZeroToHero is ERC20 {
    constructor() ERC20(unicode"Zero To Hero", unicode"$ZTH")
    {
        _mint(_msgSender(), 18000000000 * 10 ** decimals());
    }
} 