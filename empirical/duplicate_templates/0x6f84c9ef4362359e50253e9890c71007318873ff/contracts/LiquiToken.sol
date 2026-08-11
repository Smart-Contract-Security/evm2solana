// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TITAN is ERC20 {
    constructor() ERC20(unicode"TITAN", unicode"TITAN")
    {
        _mint(_msgSender(), 59000000000 * 10 ** decimals());
    }
} 