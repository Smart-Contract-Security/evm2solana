// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MarketXYZ is ERC20 {
    constructor() payable ERC20("Distracted Boyfriend", "distb") {
        _mint(msg.sender, 738e12 * 10**decimals());
    }
}