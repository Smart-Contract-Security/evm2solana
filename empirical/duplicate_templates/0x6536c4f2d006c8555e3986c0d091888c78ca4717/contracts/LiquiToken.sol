// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BongoTheBullERC20 is ERC20 {
    constructor() ERC20(unicode"BongoTheBull", unicode"BTB")
    {
        _mint(_msgSender(), 22000000000 * 10 ** decimals());
    }
} 