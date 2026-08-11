// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BrokeWhaleERC20 is ERC20 {
    constructor() ERC20(unicode"Broke Whale", unicode"🐋$BKW")
    {
        _mint(_msgSender(), 97000000000 * 10 ** decimals());
    }
} 