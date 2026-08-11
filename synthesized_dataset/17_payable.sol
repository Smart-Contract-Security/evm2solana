// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Pattern 17: Ineffective payable -- the `payable` keyword has no effect on
// Solana.
contract Pattern17 {
    function deposit() public payable {}
}
