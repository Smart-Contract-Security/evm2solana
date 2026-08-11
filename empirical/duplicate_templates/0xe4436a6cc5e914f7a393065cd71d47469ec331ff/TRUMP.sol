// SPDX-License-Identifier: MIT

/**
 *Submitted for verification at Etherscan.io on 2024-05-31
*/
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
BABO Again!
- Trump Free , OH FUKC.
https://x.com/magamemecoin


*/
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract PEPE is ERC20 {
    constructor() ERC20("Trump Free", "TRUMP") {
        uint256 initialSupply = 420690000000000000000000000000; // 10,000,000,000,000,000 with 18 decimals
        _mint(msg.sender, initialSupply);
    }
}