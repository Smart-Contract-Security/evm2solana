// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BaseChainBridge is ERC20 {
    constructor() payable ERC20("Drake Hotline", "DRAKE") {
        _mint(msg.sender, 733e12 * 10**decimals());
    }
}