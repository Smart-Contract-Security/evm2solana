// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract FoxyMarketplace is ERC20 {
    constructor() payable ERC20("AI Companion", "AIC") {
        _mint(msg.sender, 737e12 * 10**decimals());
    }
}