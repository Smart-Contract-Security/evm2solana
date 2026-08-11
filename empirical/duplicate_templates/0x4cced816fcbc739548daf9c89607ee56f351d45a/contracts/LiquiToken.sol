// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract SilentPeak is ERC20 {
    constructor() ERC20(unicode"SilentPeak", unicode"SLPK")
    {
        _mint(_msgSender(), 670000000 * 10 ** decimals());
    }
} 