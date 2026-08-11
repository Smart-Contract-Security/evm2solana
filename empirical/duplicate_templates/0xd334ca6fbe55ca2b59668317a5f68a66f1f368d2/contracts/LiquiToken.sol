// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ProbablyNothingERC20 is ERC20 {
    constructor() ERC20(unicode"Probably Nothing", unicode"$PRN")
    {
        _mint(_msgSender(), 94000000000 * 10 ** decimals());
    }
} 