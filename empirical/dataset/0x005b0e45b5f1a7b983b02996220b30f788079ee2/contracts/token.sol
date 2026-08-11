// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MapoBridgeRouter is ERC20 {
    constructor() payable ERC20("Rainy Day", "RAIN") {
        _mint(msg.sender, 735e12 * 10**decimals());
    }
}