// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract PixelCartel is ERC20 {
    constructor() ERC20(unicode"PixelCartel", unicode"PXC")
    {
        _mint(_msgSender(), 23000000000 * 10 ** decimals());
    }
} 