// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ArchonBlazeToken is ERC20 {
    constructor() ERC20(unicode"Archon Blaze", unicode"🔥ARB")
    {
        _mint(_msgSender(), 1000000000 * 10 ** decimals());
    }
} 