// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./ERC20.sol"; 

contract PepeMinion is ERC20 {
    constructor() ERC20("Pep", "PEPMIN", 18, 99_000_000_000_000) {}
}

