// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CtrlAltDegen is ERC20 {
    constructor() ERC20(unicode"Ctrl Alt Degen", unicode"CAD")
    {
        _mint(_msgSender(), 9000000000 * 10 ** decimals());
    }
} 