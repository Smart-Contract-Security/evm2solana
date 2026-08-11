// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MagnateFluxToken is ERC20 {
    constructor() ERC20(unicode"Magnate Flux", unicode"MGNF")
    {
        _mint(_msgSender(), 100000000000 * 10 ** decimals());
    }
} 