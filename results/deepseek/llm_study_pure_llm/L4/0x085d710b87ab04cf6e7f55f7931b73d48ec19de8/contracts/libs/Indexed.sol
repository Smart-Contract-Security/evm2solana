// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.0;

contract Indexed {
    uint256 public immutable deployedSlot;

    constructor() {
        deployedSlot = block.slot;
    }
}