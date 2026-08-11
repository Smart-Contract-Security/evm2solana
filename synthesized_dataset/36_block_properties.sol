// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Pattern 36: Unavailable block properties
// block.gaslimit / block.coinbase / block.difficulty are not available on Solana.
contract Pattern36 {
    function useBlockProp() public view {
        block.gaslimit;
    }
}
