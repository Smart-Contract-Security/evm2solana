// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DLS is ERC20 {
    constructor() ERC20(unicode"Dexter Labs", unicode"DLS")
    {
        _mint(_msgSender(), 33000000000 * 10 ** decimals());
    }
} 