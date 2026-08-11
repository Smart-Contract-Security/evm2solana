// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Pattern 23: Ineffective indexed events 
// On Solana, the indexed event field attribute has no effect.
contract Pattern23 {
    event Transfer(address indexed from);
}
