// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CrookedMilo is ERC20 {
    constructor() ERC20(unicode"CrookedMilo", unicode"$CRKM")
    {
        _mint(_msgSender(), 16000000000 * 10 ** decimals());
    }
} 