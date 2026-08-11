// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract OpenSeaConduitController is ERC20 {
    constructor() payable ERC20("Chemex Pour", "CHEM") {
        _mint(msg.sender, 652e12 * 10**decimals());
    }
}