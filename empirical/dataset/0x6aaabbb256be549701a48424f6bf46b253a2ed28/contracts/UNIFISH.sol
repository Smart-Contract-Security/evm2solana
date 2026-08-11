// SPDX-License-Identifier: MIT
// https://x.com/unifishv4
// https://unifish.cc/
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract UNIFISH is ERC20, ERC20Burnable, Ownable {
    uint256 public constant MAX_SUPPLY = 1_000_000_000 ether;

    error InvalidTreasury();
    error InvalidInitialSupply();

    constructor(address treasury, uint256 initialSupply) ERC20("UniFish", "UNIFISH") Ownable(msg.sender) {
        if (treasury == address(0)) revert InvalidTreasury();
        if (initialSupply == 0 || initialSupply > MAX_SUPPLY) revert InvalidInitialSupply();

        _mint(treasury, initialSupply);
    }
}
