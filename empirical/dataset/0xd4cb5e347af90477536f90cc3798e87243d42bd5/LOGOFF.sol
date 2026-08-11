// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract LogOffNow is ERC20 {
    constructor(address initialOwner) ERC20("Log Off Now", "LOGOFF") {
        _mint(initialOwner, 10_000_000 * 10 ** decimals());
    }
}