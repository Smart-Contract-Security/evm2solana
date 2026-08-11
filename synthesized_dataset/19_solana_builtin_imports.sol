// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Pattern 19: Required Solana builtin imports
// Some builtin functionality is only available after importing. 

import 'solana';

contract Pattern19 {
    function info() public view {
        AccountInfo ai = tx.accounts[0];
    }
}