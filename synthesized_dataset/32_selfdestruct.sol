// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Pattern 32: Unavailable selfdestruct()
// selfdestruct does not exist on Solana.
contract Pattern32 {
    function destroy(address payable to) public {
        selfdestruct(to);
    }
}
