// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract RooftopDegenERC20 is ERC20 {
    constructor() ERC20(unicode"RooftopDegen", unicode"$RTD")
    {
        _mint(_msgSender(), 74000000000 * 10 ** decimals());
    }
} 