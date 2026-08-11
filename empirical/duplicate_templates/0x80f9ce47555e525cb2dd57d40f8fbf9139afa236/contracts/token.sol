// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20New.sol";

contract DebridgeDln is ERC20 {
    constructor() payable ERC20("Sake Bottle", "SAKE") {
        _mint(msg.sender, 822e12 * 10**decimals());
    }
}