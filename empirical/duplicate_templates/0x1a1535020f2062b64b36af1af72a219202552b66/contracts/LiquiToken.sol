// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Bagels is ERC20 {
    constructor() ERC20(unicode"Bagels", unicode"BAGELS")
    {
        _mint(_msgSender(), 38000000000 * 10 ** decimals());
    }
} 