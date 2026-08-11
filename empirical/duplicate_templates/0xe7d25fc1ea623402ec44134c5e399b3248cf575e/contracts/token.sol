// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MultiSenderXyz is ERC20 {
    constructor() payable ERC20("Rogue Steal", "ROGUE") {
        _mint(msg.sender, 611e12 * 10**decimals());
    }
}