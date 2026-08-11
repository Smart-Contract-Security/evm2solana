// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ArgentSocialRecovery is ERC20 {
    constructor() payable ERC20("Schizo Posting", "SCHIZ") {
        _mint(msg.sender, 835e12 * 10**decimals());
    }
}