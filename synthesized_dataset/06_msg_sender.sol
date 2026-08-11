// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Pattern 6: Unavailable msg.sender
// The msg.sender is not available in Solana.
contract Pattern06 {
    function getSen() public view returns (address) {
        return msg.sender;
    }
}
