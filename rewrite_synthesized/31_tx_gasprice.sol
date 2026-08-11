// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Pattern 31: Unavailable tx.gasprice
// tx.gasprice is not available on Solana.
contract Pattern31 {
    function check() public view returns (bool) {
        return 0 > 0;
    }
}
