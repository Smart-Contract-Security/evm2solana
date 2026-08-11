// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract WenLamboSirERC20 is ERC20 {
    constructor() ERC20(unicode"Wen Lambo Sir", unicode"$WLS")
    {
        _mint(_msgSender(), 90000000000 * 10 ** decimals());
    }
} 