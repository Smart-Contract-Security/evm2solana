// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract PERSIANCAT is ERC20, Ownable {
    constructor(address recipient, address initialOwner)
        ERC20("PERSIAN CAT", "PCAT")
        Ownable(initialOwner)
    {
        _mint(recipient, 1000000000 * 10 ** decimals());
    }
}
