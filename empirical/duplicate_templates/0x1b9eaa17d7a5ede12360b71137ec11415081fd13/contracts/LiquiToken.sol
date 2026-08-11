// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract GeneralPumpERC20 is ERC20 {
    constructor() ERC20(unicode"General Pump", unicode"$GNRP")
    {
        _mint(_msgSender(), 78000000000 * 10 ** decimals());
    }
} 