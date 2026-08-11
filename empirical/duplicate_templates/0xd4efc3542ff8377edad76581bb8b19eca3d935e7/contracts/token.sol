// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract GammaSwapPool is ERC20 {
    constructor() payable ERC20("Moka Pot", "MOKA") {
        _mint(msg.sender, 831e12 * 10**decimals());
    }
}