// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BreezyLouERC20 is ERC20 {
    constructor() ERC20(unicode"Breezy Lou", unicode"BRZL")
    {
        _mint(_msgSender(), 92000000000 * 10 ** decimals());
    }
} 