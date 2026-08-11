// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract NgmiNoMore is ERC20 {
    constructor() ERC20(unicode"Ngmi No More", unicode"$NNM")
    {
        _mint(_msgSender(), 45000000000 * 10 ** decimals());
    }
} 