// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CaptainLiquidityToken is ERC20 {
    constructor() ERC20(unicode"Captain Liquidity", unicode"🌊CPL")
    {
        _mint(_msgSender(), 97000000000 * 10 ** decimals());
    }
} 