// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DukeOfDegen is ERC20 {
    constructor() ERC20(unicode"Duke Of Degen", unicode"👑DOD")
    {
        _mint(_msgSender(), 12000000000 * 10 ** decimals());
    }
} 