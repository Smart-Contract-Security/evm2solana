// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Pattern 29: Changed msg.sig width
// The msg.sig assumes the semantic role of a bytes8 discriminator.
contract Pattern29 {
    function selector() public pure {
        bytes4 s = msg.sig;
    }
}
