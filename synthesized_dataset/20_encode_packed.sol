// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Pattern 20: Little-endian packed encoding -- abi.encodePacked uses
// little-endian encoding on Solana (SBF), unlike big-endian EVM.
contract Pattern20 {
    function pack(uint64 a, address b) public pure returns (bytes memory) {
        return abi.encodePacked(a, b);
    }
}
