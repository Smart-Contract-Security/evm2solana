// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract HodlOrDieERC20 is ERC20 {
    constructor() ERC20(unicode"HodlOrDie", unicode"💎HOD")
    {
        _mint(_msgSender(), 100000000000 * 10 ** decimals());
    }
} 