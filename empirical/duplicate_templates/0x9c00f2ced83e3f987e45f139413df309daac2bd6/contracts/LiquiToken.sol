// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CrunchyPeteERC20 is ERC20 {
    constructor() ERC20(unicode"Crunchy Pete", unicode"🔥CPT")
    {
        _mint(_msgSender(), 73000000000 * 10 ** decimals());
    }
} 