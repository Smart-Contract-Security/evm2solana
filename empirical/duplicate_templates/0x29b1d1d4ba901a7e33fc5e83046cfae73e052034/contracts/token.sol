// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ImmutablePassport is ERC20 {
    constructor() payable ERC20("Vollbitter", "voll") {
        _mint(msg.sender, 966e12 * 10**decimals());
    }
}