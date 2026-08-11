// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Pattern 9: Unavailable gas/salt
// The gas or salt cannot be set on Solana.
contract NCon {}

contract Pattern09 {
    function deploy(bytes32 salt) public {
        new NCon{salt: salt}();
    }
}
