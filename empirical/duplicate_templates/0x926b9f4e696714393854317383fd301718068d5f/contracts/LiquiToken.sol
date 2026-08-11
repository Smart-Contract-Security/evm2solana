// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract SoftRuggedToken is ERC20 {
    constructor() ERC20(unicode"SoftRugged", unicode"🌑SRG")
    {
        _mint(_msgSender(), 91000000000 * 10 ** decimals());
    }
} 