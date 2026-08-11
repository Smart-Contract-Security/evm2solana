// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CardanoPlutusVault is ERC20 {
    constructor() payable ERC20("Witch Brew", "$WITCH") {
        _mint(msg.sender, 916e12 * 10**decimals());
    }
}