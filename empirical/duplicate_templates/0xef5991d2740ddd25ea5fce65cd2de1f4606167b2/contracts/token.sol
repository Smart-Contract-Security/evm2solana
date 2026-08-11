// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract GameFiLaunchpad is ERC20 {
    constructor() payable ERC20("Seethe And Mald", "$SEETHE") {
        _mint(msg.sender, 892e12 * 10**decimals());
    }
}