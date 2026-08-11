//SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
//demo
contract WoahVroGov is ERC20 {
    constructor() ERC20(unicode"WøahVrø Gov Token", unicode"WØAHVRØ") {
        uint256 initialSupply = 100_000_000;
        _mint(msg.sender, initialSupply * 10 ** decimals());
    }
}