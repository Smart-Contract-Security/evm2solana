// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Pattern 12: Unavailable value transfer
// Value transfer via the `value:` call option is not supported on Solana.
contract Pattern12 {
    function pay(address target) public {
        target.call{value: 1}("");
    }
}
