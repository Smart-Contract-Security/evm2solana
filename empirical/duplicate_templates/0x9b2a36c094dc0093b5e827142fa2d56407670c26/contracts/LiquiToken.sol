// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract SilentMarshERC20 is ERC20 {
    constructor() ERC20(unicode"Silent Marsh", unicode"SLMR")
    {
        _mint(_msgSender(), 28000000000 * 10 ** decimals());
    }
} 