// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Pattern 7: Unavailable ecrecover()
// There is no ecrecover() builtin function because Solana does not use the ECDSA algorithm
contract Pattern07 {
    function recover(bytes32 h, uint8 v, bytes32 r, bytes32 s) public pure {
        ecrecover(h, v, r, s);
    }
}
