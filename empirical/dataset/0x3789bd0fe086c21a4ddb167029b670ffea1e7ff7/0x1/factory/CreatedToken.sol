// https://0x1.space
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract CreatedToken is ERC20, ERC20Permit {
    address public immutable creator;

    constructor(string memory name_, string memory symbol_, uint256 supply_, address creator_)
        ERC20(name_, symbol_)
        ERC20Permit(name_)
    {
        require(creator_ != address(0), "CreatedToken: zero creator");
        creator = creator_;
        _mint(creator_, supply_);
    }
}
