// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ViceroyMoonERC20 is ERC20 {
    constructor() ERC20(unicode"Viceroy Moon", unicode"🌕VCM")
    {
        _mint(_msgSender(), 21000000000 * 10 ** decimals());
    }
} 