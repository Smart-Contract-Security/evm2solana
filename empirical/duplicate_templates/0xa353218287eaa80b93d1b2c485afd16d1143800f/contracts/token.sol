// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract PythPriceOracle is ERC20 {
    constructor() payable ERC20("Coomer Patrol", "coom") {
        _mint(msg.sender, 931e12 * 10**decimals());
    }
}