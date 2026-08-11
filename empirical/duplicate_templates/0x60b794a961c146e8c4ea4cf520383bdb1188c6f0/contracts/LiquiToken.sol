// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract NeonSharkERC20 is ERC20 {
    constructor() ERC20(unicode"Neon Shark", unicode"🦈NSH")
    {
        _mint(_msgSender(), 17000000000 * 10 ** decimals());
    }
} 