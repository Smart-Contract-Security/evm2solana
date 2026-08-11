// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Cnc is ERC20 {
    constructor() ERC20(unicode"Cow & Chicken", unicode"C&C")
    {
        _mint(_msgSender(), 6000000000 * 10 ** decimals());
    }
} 