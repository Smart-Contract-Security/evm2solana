// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ChillyMax is ERC20 {
    constructor() ERC20(unicode"ChillyMax", unicode"🧊CHM")
    {
        _mint(_msgSender(), 30000000000 * 10 ** decimals());
    }
} 