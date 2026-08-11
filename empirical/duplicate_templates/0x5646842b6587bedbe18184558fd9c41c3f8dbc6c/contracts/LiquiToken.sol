// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract EnvoyFrost is ERC20 {
    constructor() ERC20(unicode"Envoy Frost", unicode"🧊ENF")
    {
        _mint(_msgSender(), 40000000000 * 10 ** decimals());
    }
} 