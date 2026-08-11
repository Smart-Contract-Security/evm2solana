// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20New.sol";

contract MaverickRouter is ERC20 {
    constructor() payable ERC20("Arak Lebanese", "$ARAK") {
        _mint(msg.sender, 824e12 * 10**decimals());
    }
}