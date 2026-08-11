// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Pattern 25: Unavailable gas on external calls
// The gas cannot be set on Solana for external calls.
interface ICallPa {
    function test() external;
}

contract Pattern25 {
    function callWithGas(address target) public {
        ICallPa(target).test{gas: 1000}();
    }
}
