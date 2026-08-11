// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IAccessPredicate
/// @notice ERC-8257 standard interface — controls which agents may access a tool
/// @dev Implement this to gate access by NFT holding, subscription, ZK-proof, etc.
interface IAccessPredicate {
    /// @notice Check if `account` satisfies the access condition
    /// @param account  The agent's Ethereum address
    /// @param data     Optional context data (e.g. tokenId, proof bytes)
    /// @return True if access is granted
    function hasAccess(address account, bytes calldata data) external view returns (bool);
}
