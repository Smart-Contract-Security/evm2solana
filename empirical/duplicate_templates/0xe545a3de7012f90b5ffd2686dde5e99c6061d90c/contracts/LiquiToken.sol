// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract PixelMafia is ERC20 {
    constructor() ERC20(unicode"Pixel Mafia", unicode"$PXMF")
    {
        _mint(_msgSender(), 45000000000 * 10 ** decimals());
    }
} 