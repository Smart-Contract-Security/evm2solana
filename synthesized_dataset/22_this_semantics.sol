// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Pattern 22: Changed this semantics
// Contracts cannot be used as first-class types in function parameters, return values, or local variables.
contract Pattern22 {
    function getTh() public view returns (address) {
        return address(this);
    }
}
