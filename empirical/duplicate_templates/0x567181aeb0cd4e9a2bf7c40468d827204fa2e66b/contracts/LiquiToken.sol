// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract SmokeyGainsToken is ERC20 {
    constructor() ERC20(unicode"SmokeyGains", unicode"$SKGN")
    {
        _mint(_msgSender(), 11000000000 * 10 ** decimals());
    }
} 