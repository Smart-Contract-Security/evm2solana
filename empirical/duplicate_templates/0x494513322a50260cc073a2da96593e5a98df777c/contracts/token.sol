// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract KaminoLendingMarket is ERC20 {
    constructor() payable ERC20("Fairy Tale", "FAIRY") {
        _mint(msg.sender, 716e12 * 10**decimals());
    }
}