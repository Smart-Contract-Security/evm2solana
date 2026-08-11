// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TulipProtocolVault is ERC20 {
    constructor() payable ERC20("Dragon Fire", "drag") {
        _mint(msg.sender, 563e12 * 10**decimals());
    }
}