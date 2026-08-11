// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract EnergyWebFlex is ERC20 {
    constructor() payable ERC20("Pegasus Wings", "PEG") {
        _mint(msg.sender, 936e12 * 10**decimals());
    }
}