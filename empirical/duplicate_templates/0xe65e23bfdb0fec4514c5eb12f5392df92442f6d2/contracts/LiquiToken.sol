// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MainCharacterToken is ERC20 {
    constructor() ERC20(unicode"Main Character", unicode"🌟MCH")
    {
        _mint(_msgSender(), 35000000000 * 10 ** decimals());
    }
} 