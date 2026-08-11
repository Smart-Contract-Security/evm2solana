// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract WenAirdropERC20 is ERC20 {
    constructor() ERC20(unicode"Wen Airdrop", unicode"$WNA")
    {
        _mint(_msgSender(), 6000000000 * 10 ** decimals());
    }
} 