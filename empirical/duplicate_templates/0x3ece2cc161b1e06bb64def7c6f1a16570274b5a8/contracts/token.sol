// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract EulerSwapHook is ERC20 {
    constructor() payable ERC20("Bananenlikor", "BANAN") {
        _mint(msg.sender, 805e12 * 10**decimals());
    }
}