// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract GooseFXSsl is ERC20 {
    constructor() payable ERC20("Beta Cuck", "beta") {
        _mint(msg.sender, 788e12 * 10**decimals());
    }
}