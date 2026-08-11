// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Pattern 35: Changed block.number semantics
// On Solana, block.number gives the slot number rather than the block height.
contract Pattern35 {
    function currentBlock() public view {
        block.number;
    }
}
