// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract FloorDaoStaking is ERC20 {
    constructor() payable ERC20("Safe Moon Plus", "SMP") {
        _mint(msg.sender, 839e12 * 10**decimals());
    }
}