// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Pattern 26: Unavailable delegatecall 
// delegatecall is not available on Solana.
contract Pattern26 {
    function forward(address target, bytes calldata data) public {
        target.delegatecall(data);
    }
}
