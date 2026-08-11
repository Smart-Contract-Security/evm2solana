// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Pattern 30b : abi.encodeWithSignature 
contract Pattern30b {
    function encode(uint64 x) public pure returns (bytes memory) {
        return abi.encodeWithSignature("f(uint64)", x);
    }
}
