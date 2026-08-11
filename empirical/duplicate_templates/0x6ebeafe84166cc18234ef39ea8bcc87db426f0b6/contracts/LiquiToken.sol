// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract FrozenRavenToken is ERC20 {
    constructor() ERC20(unicode"FrozenRaven", unicode"🌑FRV")
    {
        _mint(_msgSender(), 8000000000 * 10 ** decimals());
    }
} 