// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract StargatePool is ERC20 {
    constructor() payable ERC20("Joghurtlikor", "JOGH") {
        _mint(msg.sender, 548e12 * 10**decimals());
    }
}