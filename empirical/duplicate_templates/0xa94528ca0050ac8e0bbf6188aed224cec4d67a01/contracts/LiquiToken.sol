// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract LadyMoonbagERC20 is ERC20 {
    constructor() ERC20(unicode"Lady Moonbag", unicode"🌙LMB")
    {
        _mint(_msgSender(), 29000000000 * 10 ** decimals());
    }
} 