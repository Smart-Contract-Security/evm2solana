// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Pattern 11b: Unavailable error definitions
//  reverts with error messages is not yet working for Solana.
contract Pattern11b {

    function errorMsg() public pure {
        revert("error Msg");
    }
}
