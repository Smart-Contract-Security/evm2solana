// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract IvoryQuarterToken is ERC20 {
    constructor() ERC20(unicode"IvoryQuarter", unicode"💎IVQ")
    {
        _mint(_msgSender(), 72000000000 * 10 ** decimals());
    }
} 