// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Pattern 15: Required @program_id
// When making external calls on Solana, the target program must be specified. 
// Solang uses `@program_id` for this adaptation.

interface NCon {
    function callPattern() external;
}

contract Pattern15 {
    function callExternal(address target) public {
        NCon(target).callPattern();
    }
}
