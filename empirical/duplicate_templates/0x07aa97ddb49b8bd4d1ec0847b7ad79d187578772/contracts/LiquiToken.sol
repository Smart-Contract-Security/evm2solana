// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract GlassApeERC20 is ERC20 {
    constructor() ERC20(unicode"Glass Ape", unicode"GLA")
    {
        _mint(_msgSender(), 42000000000 * 10 ** decimals());
    }
} 