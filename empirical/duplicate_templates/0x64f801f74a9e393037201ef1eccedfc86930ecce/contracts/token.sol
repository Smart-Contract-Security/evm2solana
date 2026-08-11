// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract QredoNetworkBridge is ERC20 {
    constructor() payable ERC20("Apfelschnaps", "APFEL") {
        _mint(msg.sender, 770e12 * 10**decimals());
    }
}