// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract FraxlendPair is ERC20 {
    constructor() payable ERC20("Pixel Pepe", "PXP") {
        _mint(msg.sender, 927e12 * 10**decimals());
    }
}