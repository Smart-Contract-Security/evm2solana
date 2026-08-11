// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BeeHiveMonitoringToken is ERC20 {
    constructor() ERC20("Bee Hive Monitoring Token", "BHM") {
        _mint(msg.sender, 100_000_000 * 10 ** decimals());
    }
}