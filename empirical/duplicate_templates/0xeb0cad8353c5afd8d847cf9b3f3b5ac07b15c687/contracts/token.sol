// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract FuelChainState is ERC20 {
    constructor() payable ERC20("Aikido Flow", "aiki") {
        _mint(msg.sender, 690e12 * 10**decimals());
    }
}