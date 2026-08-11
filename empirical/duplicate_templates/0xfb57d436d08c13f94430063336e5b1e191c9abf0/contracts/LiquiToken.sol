// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract GreasyPalmer is ERC20 {
    constructor() ERC20(unicode"Greasy Palmer", unicode"GRSP")
    {
        _mint(_msgSender(), 700000000 * 10 ** decimals());
    }
} 