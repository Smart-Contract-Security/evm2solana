// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract NeonDocksERC20 is ERC20 {
    constructor() ERC20(unicode"Neon Docks", unicode"⚡NDK")
    {
        _mint(_msgSender(), 31000000000 * 10 ** decimals());
    }
} 