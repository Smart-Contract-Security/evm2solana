// SPDX-License-Identifier: MIT
/**
 *Submitted for verification at Etherscan.io on 2024-05-31
*/
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
FEW Again!
- FLOKI in a memes world , OH FUKC.
https://x.com/realflokiinu
https://www.floki.com/
https://telegram.me/FlokiInuToken


*/
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract PEPE is ERC20 {
    constructor() ERC20("FLOKI in a memes world", "FEW") {
        uint256 initialSupply = 1000000000000000000000000000000; // 10,000,000,000,000,000 with 18 decimals
        _mint(msg.sender, initialSupply);
    }
}