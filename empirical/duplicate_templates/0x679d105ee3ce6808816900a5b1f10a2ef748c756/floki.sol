// SPDX-License-Identifier: MIT
/**
 *Submitted for verification at Etherscan.io on 2024-05-31
*/
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
PEW Again!
- PEOPLE in a memes world , OH FUKC.
https://x.com/constitutiondao
https://www.constitutiondao.com/


*/
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract PEPE is ERC20 {
    constructor() ERC20("PEOPLE in a memes world", "PEW") {
        uint256 initialSupply = 1000000000000000000000000000000; // 10,000,000,000,000,000 with 18 decimals
        _mint(msg.sender, initialSupply);
    }
}