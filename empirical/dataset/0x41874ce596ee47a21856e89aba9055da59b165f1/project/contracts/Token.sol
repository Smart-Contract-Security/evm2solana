// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;


//Stalios 

// Website : stalios.com
// Community: chat.stalios.com
// Twitter: x.com/0xStalios

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract STA is ERC20 {
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 initialSupply_
    ) ERC20(name_, symbol_) {
        _mint(msg.sender, initialSupply_);
    }
}
