// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Pattern 13: Unavailable Yul builtins
// Inline-assembly builtins are not available on Solana.
contract Pattern13 {
    function useAsm() public view {
        assembly {
            pop(chainid())
        }
    }
}
