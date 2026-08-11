// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Pattern 18: Unavailable receive()
// receive() functions are not permitted on the Solana target.
contract Pattern18 {
    receive() external payable {}
}
