// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MerlinChainBridge is ERC20 {
    constructor() payable ERC20("Snowflake Special", "snow") {
        _mint(msg.sender, 717e12 * 10**decimals());
    }
}