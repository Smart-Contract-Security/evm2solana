// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ObsidianCoveToken is ERC20 {
    constructor() ERC20(unicode"Obsidian Cove", unicode"🌑OBC")
    {
        _mint(_msgSender(), 22000000000 * 10 ** decimals());
    }
} 