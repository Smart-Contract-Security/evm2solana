// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20}    from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable}  from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title $RUSH — fixed-supply ERC-20.
 *
 *   total = 100_000_000 * 1e18
 *
 * Allocations (all minted at deploy, transferred by deployer to:):
 *   15_000_000  → AMM seed pool (P2 pair creation)
 *   80_000_000  → RushClaim treasury (P3 claim pool)
 *    5_000_000  → dev / ops
 *
 * No mint after deploy. No transfer tax. Burn happens by sending to 0xdead.
 */
contract RushToken is ERC20, Ownable {
    uint256 public constant TOTAL_SUPPLY = 100_000_000 * 1e18;

    constructor(address treasury)
        ERC20("Rush", "RUSH")
        Ownable(msg.sender)
    {
        _mint(treasury, TOTAL_SUPPLY);
    }
}
