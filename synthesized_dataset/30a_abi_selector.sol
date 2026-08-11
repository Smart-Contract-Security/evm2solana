// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Pattern 30a : abi.encodeWithSelector
contract Pattern30a {
    function encode(uint64 x) public pure returns (bytes memory) {
        return abi.encodeWithSelector(bytes4(0x12345678), x);
    }
}
