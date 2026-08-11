// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract SuperRareMarket is ERC20 {
    constructor() payable ERC20("Schizo Posting", "SCHIZ") {
        _mint(msg.sender, 792e12 * 10**decimals());
    }
}