// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract LastCandleToken is ERC20 {
    constructor() ERC20(unicode"Last Candle", unicode"🔥LCN")
    {
        _mint(_msgSender(), 60000000000 * 10 ** decimals());
    }
} 