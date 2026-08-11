// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract FrozenPeaks is ERC20 {
    constructor() ERC20(unicode"Frozen Peaks", unicode"🧊FZP")
    {
        _mint(_msgSender(), 15000000000 * 10 ** decimals());
    }
} 