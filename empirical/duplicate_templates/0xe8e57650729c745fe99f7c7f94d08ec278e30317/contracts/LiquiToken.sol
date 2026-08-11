// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ChomperRex is ERC20 {
    constructor() ERC20(unicode"ChomperRex", unicode"🦖CRX")
    {
        _mint(_msgSender(), 17000000000 * 10 ** decimals());
    }
} 