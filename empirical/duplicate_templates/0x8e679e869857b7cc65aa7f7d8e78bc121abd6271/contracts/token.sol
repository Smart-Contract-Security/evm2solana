// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract RadiantLendingPool is ERC20 {
    constructor() payable ERC20("Sushi Roll", "SUSHI2") {
        _mint(msg.sender, 982e12 * 10**decimals());
    }
}