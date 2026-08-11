// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract WallyTheDipToken is ERC20 {
    constructor() ERC20(unicode"WallyTheDip", unicode"WTD")
    {
        _mint(_msgSender(), 75000000000 * 10 ** decimals());
    }
} 