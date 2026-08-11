// SPDX-License-Identifier: MIT
/**
 *Submitted for verification at Etherscan.io on 2024-05-31
*/

/**
$Bew Again!
- Bertha in a Jenner world! , OH FUKC.
Buy tax=0 
Sell tax=0
https://x.com/Caitlyn_Jenner
https://fairnessfirst.us/
https://www.usmagazine.com/celebrity-news/news/caitlyn-jenner-adopts-new-puppy-bertha-see-the-pic-w485996/
*/
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract PEPE is ERC20 {
    constructor() ERC20("Bertha in a Jenner world", "Bew") {
        uint256 initialSupply = 42069000000000000000000000000000000; // 10,000,000,000,000,000 with 18 decimals
        _mint(msg.sender, initialSupply);
    }
}