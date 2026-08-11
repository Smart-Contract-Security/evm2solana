// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Pattern 10: Unavailable try-catch
// Try-catch statements do not work on Solana.
interface NCon {
    function f() external;
}

contract Pattern10 {
    function attempt(address target) public {
        try NCon(target).f() {
        } catch {
        }
    }
}
