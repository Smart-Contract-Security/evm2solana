// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Pattern 14: ERC-20/SPL token gap
// The ERC-20 interface is not compatible with Solana at the moment. Solana uses SPL Token
interface IERC20 {
    function transfer(address to, uint64 amount) external returns (bool);
}

contract Pattern14 is IERC20 {
    function transfer(address to, uint64 amount) external returns (bool) {
        return true;
    }
}
