// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Surface GateCoin uses to credit a wallet's spin entitlement on first mint.
interface IRushClaim {
    function creditSpin(address user, uint256 amount) external;
}
