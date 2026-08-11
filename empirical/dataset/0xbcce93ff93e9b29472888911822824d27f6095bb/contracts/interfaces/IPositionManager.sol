// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal interface for Uniswap V4 PositionManager (ERC721 + liquidity)
interface IPositionManager {
    /// @notice Execute a batch of liquidity modifications encoded as actions
    /// @param unlockData ABI-encoded (bytes actions, bytes[] params)
    /// @param deadline Timestamp by which the transaction must be mined
    function modifyLiquidities(
        bytes calldata unlockData,
        uint256 deadline
    ) external payable;

    /// @notice Returns the next token ID to be minted
    function nextTokenId() external view returns (uint256);

    // ----- ERC721 functions -----

    /// @notice Safely transfers a position NFT
    function safeTransferFrom(address from, address to, uint256 tokenId) external;

    /// @notice Approve a single token
    function approve(address to, uint256 tokenId) external;

    /// @notice Approve/revoke an operator for all tokens
    function setApprovalForAll(address operator, bool approved) external;

    /// @notice Returns the owner of a position NFT
    function ownerOf(uint256 tokenId) external view returns (address);
}
