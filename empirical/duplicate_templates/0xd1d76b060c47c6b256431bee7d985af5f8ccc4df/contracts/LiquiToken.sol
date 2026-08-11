// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract NovaPandaERC20 is ERC20 {
    constructor() ERC20(unicode"NovaPanda", unicode"🐼NPD")
    {
        _mint(_msgSender(), 32000000000 * 10 ** decimals());
    }
} 