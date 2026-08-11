// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract KusamaBridge is ERC20 {
    constructor() payable ERC20("Goliath Strong", "GOLI") {
        _mint(msg.sender, 900e12 * 10**decimals());
    }
}