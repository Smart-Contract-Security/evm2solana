// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Pattern 24: Unavailable tx.origin
// The address that started this transaction. Not available on Polkadot or Solana.
contract Pattern24 {
    function getOrigin() public view returns (address) {
        return tx.origin;
    }
}
