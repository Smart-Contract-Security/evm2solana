// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Pattern 38: Ethereum currency units
// ether/gwei/wei produce warnings when not targeting Ethereum.
contract Pattern38 {
    function useUnit() public pure {
        1 ether;
    }
}
