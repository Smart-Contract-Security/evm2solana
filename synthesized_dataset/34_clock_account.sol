// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Pattern 34: Required clock account
// Using any block field (e.g. block.timestamp) requires the Solana clock account.
contract Pattern34 {
    function useClock() public view {
        block.timestamp;
    }
}
