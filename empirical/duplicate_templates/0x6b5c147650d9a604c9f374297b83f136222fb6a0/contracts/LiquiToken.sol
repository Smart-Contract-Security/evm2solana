// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract LiegePumpERC20 is ERC20 {
    constructor() ERC20(unicode"Liege Pump", unicode"🌟LGP")
    {
        _mint(_msgSender(), 67000000000 * 10 ** decimals());
    }
} 