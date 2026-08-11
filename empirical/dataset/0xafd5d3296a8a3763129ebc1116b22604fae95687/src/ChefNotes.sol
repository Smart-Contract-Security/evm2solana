// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title ChefNotes
 * @notice The ONLY official announcement channel for Sushi v4 — fully on-chain.
 *
 *  - Only the owner (the deployer wallet) can post. A note is authentic if and only if it was emitted
 *    by THIS contract from the owner wallet, so there is nothing to impersonate: no Twitter, no Telegram,
 *    no Discord — just signed, on-chain notes.
 *  - Notes are emitted as events (cheap) and are PERMANENT: they cannot be edited or deleted.
 *  - The frontend reads the `Note` event log; `noteCount` lets it verify it fetched every note.
 *
 * Holds no funds. No length cap — only the owner can post, so the gas they pay is the natural limit.
 */
contract ChefNotes {
    address public owner;
    uint256 public noteCount;

    event Note(uint256 indexed id, string message, uint256 timestamp);
    event OwnerUpdated(address indexed newOwner);

    error OnlyOwner();
    error ZeroAddress();
    error Empty();

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    constructor(address owner_) {
        if (owner_ == address(0)) revert ZeroAddress();
        owner = owner_;
    }

    /// @notice Post an official note. Owner-only. Returns the note's id.
    function post(string calldata message) external onlyOwner returns (uint256 id) {
        if (bytes(message).length == 0) revert Empty();
        id = noteCount++;
        emit Note(id, message, block.timestamp);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        owner = newOwner;
        emit OwnerUpdated(newOwner);
    }
}
