// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ScruffyNedToken is ERC20 {
    constructor() ERC20(unicode"Scruffy Ned", unicode"SCFN")
    {
        _mint(_msgSender(), 88000000000 * 10 ** decimals());
    }
} 