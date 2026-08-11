// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract SovereignDripToken is ERC20 {
    constructor() ERC20(unicode"Sovereign Drip", unicode"💎SVRD")
    {
        _mint(_msgSender(), 51000000000 * 10 ** decimals());
    }
} 