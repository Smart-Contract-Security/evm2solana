// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Pattern 2: 64-bit integers 
// Solana’s virtual machine registers are 64-bit wide, so 64-bit integers uint64 and int64 are preferable over uint256 and int256.
contract Pattern02 {
    uint256 public number = 100;

    function add() public {
        number = number + 100;
    }
}
