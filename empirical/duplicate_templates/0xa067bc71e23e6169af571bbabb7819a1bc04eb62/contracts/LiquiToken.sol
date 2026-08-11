// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract GrumpyWalt is ERC20 {
    constructor() ERC20(unicode"Grumpy Walt", unicode"GRWT")
    {
        _mint(_msgSender(), 520000000 * 10 ** decimals());
    }
} 