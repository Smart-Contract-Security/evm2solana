// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Pattern 11a: Unavailable error definitions
// Error definitions is not yet working for Solana.
contract Pattern11a {
    error DefineErr();

    function errorMsg() public pure {
        revert DefineErr();
    }
}
