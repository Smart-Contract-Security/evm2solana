// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TheGraphStaking is ERC20 {
    constructor() payable ERC20("Fernet Branca", "FERN") {
        _mint(msg.sender, 565e12 * 10**decimals());
    }
}