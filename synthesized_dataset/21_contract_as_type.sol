// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Pattern 21: Contracts not usable as types
// Contracts cannot be used as types in any declaration, including state variables, parameters, return values, and local variables.
interface IToken {
    function test() external;
}

contract Pattern21 {
    IToken stored;
    function takes(IToken) public {}
}
