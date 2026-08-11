// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TouchGrass is ERC20 {
    constructor() ERC20(unicode"Touch Grass", unicode"TGS")
    {
        _mint(_msgSender(), 46000000000 * 10 ** decimals());
    }
} 