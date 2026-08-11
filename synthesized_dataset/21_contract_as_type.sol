// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Pattern 21: Contracts not usable as types
// Contracts cannot be used as first-class types in function parameters, return values, or local variables.
interface IToken {
    function test() external;
}

contract Pattern21 {
    function takes(IToken) public {}
}
