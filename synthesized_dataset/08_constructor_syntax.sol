// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Pattern 8: Changed constructor syntax
// New Contract in EVM, Contract.new in Solana
contract NCon {}

contract Pattern08 {
    function deploy() public {
        new NCon();
    }
}
