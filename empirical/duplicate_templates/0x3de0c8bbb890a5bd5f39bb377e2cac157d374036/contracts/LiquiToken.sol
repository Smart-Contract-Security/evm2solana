// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract GloomyRexERC20 is ERC20 {
    constructor() ERC20(unicode"GloomyRex", unicode"🌑GRX")
    {
        _mint(_msgSender(), 26000000000 * 10 ** decimals());
    }
} 