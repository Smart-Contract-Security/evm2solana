// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract LoopringExchange is ERC20 {
    constructor() payable ERC20("Cointreau Orange", "$COINT") {
        _mint(msg.sender, 850e12 * 10**decimals());
    }
}