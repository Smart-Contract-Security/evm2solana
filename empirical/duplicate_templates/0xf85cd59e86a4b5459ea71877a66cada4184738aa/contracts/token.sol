// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract SpookySwapMasterChef is ERC20 {
    constructor() payable ERC20("Schlehenlikor", "SCHL") {
        _mint(msg.sender, 666e12 * 10**decimals());
    }
}