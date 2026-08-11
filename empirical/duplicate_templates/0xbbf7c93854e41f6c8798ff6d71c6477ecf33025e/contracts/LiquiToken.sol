// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract NgmiClubERC20 is ERC20 {
    constructor() ERC20(unicode"Ngmi Club", unicode"NGMC")
    {
        _mint(_msgSender(), 610000000 * 10 ** decimals());
    }
} 