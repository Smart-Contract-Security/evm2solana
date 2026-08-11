// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Pattern 3: External call accounts 
// External calls and contract constructors require explicitly providing the necessary accounts.
interface ICallPa {
    function callPattern() external;
}

contract Pattern03 {
    function callExternal(address target) public {
        ICallPa(target).callPattern();
    }
}
