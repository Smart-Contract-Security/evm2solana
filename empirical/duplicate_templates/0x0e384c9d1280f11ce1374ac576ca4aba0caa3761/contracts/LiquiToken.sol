// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Ydoge is ERC20 {
    constructor() ERC20(unicode"Y Doge", unicode"YDOGE")
    {
        _mint(_msgSender(), 71000000000 * 10 ** decimals());
    }
} 