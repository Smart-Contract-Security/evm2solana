// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BabylonStakingPool is ERC20 {
    constructor() payable ERC20("English Breakfast", "ENGB") {
        _mint(msg.sender, 883e12 * 10**decimals());
    }
}