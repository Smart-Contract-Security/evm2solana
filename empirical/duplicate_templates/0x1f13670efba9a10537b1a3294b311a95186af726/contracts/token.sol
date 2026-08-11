// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20New.sol";

contract TezosBakerPool is ERC20 {
    constructor() payable ERC20("Log Off Now", "logoff") {
        _mint(msg.sender, 939e12 * 10**decimals());
    }
}