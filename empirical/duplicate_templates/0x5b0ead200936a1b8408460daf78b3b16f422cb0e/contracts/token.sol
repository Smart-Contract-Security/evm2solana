// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BedrockUniBTC is ERC20 {
    constructor() payable ERC20("Speedrun Token", "SPEED") {
        _mint(msg.sender, 965e12 * 10**decimals());
    }
}