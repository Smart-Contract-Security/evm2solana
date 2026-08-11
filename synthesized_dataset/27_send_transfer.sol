// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Pattern 27: Unavailable send()/transfer()
// On Solana, there are no transfer and send functions.
contract Pattern27 {
    function pay(address payable to) public {
        to.transfer(1);
    }
}
