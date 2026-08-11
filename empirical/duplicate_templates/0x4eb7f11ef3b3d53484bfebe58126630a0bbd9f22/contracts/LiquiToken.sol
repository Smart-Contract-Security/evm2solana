// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract RustPanda is ERC20 {
    constructor() ERC20(unicode"RustPanda", unicode"🐼RPD")
    {
        _mint(_msgSender(), 16000000000 * 10 ** decimals());
    }
} 