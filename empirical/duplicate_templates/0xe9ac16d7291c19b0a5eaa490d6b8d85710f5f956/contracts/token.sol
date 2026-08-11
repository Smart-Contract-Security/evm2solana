// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract QuestProtocolFactory is ERC20 {
    constructor() payable ERC20("Pause Menu", "pause") {
        _mint(msg.sender, 607e12 * 10**decimals());
    }
}