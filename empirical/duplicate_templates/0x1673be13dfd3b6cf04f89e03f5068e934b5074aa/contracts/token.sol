// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract OndoPointsTracker is ERC20 {
    constructor() payable ERC20("Blizzard Coin", "BLIZ") {
        _mint(msg.sender, 707e12 * 10**decimals());
    }
}