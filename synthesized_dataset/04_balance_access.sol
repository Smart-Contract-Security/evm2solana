// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Pattern 4: AccountInfo balance access
// Retrieving the balance requires accessing the AccountInfo data structure.
contract Pattern04 {
    function getBalance(address a) public view {
        a.balance;
    }
}
