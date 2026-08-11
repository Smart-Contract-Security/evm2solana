// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract RustyHank is ERC20 {
    constructor() ERC20(unicode"Rusty Hank", unicode"$RSTH")
    {
        _mint(_msgSender(), 44000000000 * 10 ** decimals());
    }
} 