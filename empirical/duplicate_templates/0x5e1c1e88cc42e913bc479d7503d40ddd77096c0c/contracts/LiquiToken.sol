// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract EclipseWhaleToken is ERC20 {
    constructor() ERC20(unicode"Eclipse Whale", unicode"🐋ECW")
    {
        _mint(_msgSender(), 94000000000 * 10 ** decimals());
    }
} 