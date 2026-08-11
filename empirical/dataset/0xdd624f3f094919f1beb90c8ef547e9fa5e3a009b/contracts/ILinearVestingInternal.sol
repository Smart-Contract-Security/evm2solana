// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

interface ILinearVestingInternal {
    event SettingsUpdated(
        uint32 indexed start,
        uint32 indexed end,
        uint256 totalVested
    );
    event Claimed(address indexed token, address indexed user, uint256 amount);

    error InvalidTimings();
    error AllocNotFound();
    error NoTokensToClaim();
    error InvalidMerkleRoot();
    error ZeroTokenAddress();
}
