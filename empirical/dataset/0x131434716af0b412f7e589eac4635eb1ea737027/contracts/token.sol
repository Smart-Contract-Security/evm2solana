// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract GearboxPool is ERC20 {
    constructor() payable ERC20("Chad Energy", "CHAD") {
        _mint(msg.sender, 994e12 * 10**decimals());
    }
}