// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BatchAuctionEngine is ERC20 {
    constructor() payable ERC20("Phoenix Rising", "PHX") {
        _mint(msg.sender, 812e12 * 10**decimals());
    }
}