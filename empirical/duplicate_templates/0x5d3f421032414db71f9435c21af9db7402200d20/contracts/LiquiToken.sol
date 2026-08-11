// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract RandomCoinERC20 is ERC20 {
    constructor() ERC20(unicode"Random Coin", unicode"RCN")
    {
        _mint(_msgSender(), 42000000000 * 10 ** decimals());
    }
} 