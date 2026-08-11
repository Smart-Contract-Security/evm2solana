// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract EmberShark is ERC20 {
    constructor() ERC20(unicode"Ember Shark", unicode"🦈EMS")
    {
        _mint(_msgSender(), 79000000000 * 10 ** decimals());
    }
} 