// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract AltSeasonERC20 is ERC20 {
    constructor() ERC20(unicode"Alt Season", unicode"🌈ALT")
    {
        _mint(_msgSender(), 82000000000 * 10 ** decimals());
    }
} 