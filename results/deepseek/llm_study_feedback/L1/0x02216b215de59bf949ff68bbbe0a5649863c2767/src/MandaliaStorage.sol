// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import 'solana';

/// @title MandaliaStorage
/// @notice Holds per-token state for the Mandalia NFT. Writes restricted to the bound NFT contract.
///         Read-only externally. ~34 bytes per token (bytes32 seed + uint16 txCount).
contract MandaliaStorage {

    address public nft;

    mapping(uint256 => bytes32) private _seeds;
    mapping(uint256 => uint16)  private _txCounts;

    string constant NotNFT_ERROR = "NotNFT";
    string constant AlreadyInitialized_ERROR = "AlreadyInitialized";

    /// @notice One-time bind to the NFT contract. Resolves the chicken-and-egg of cross-references.
    /// @dev Deploy order: (1) deploy MandaliaStorage; (2) deploy Mandalia(renderer, address(this), startTime);
    ///      (3) call MandaliaStorage.init(mandaliaAddress). After init, this contract is locked to that NFT forever.
    function init(address nft_) external {
        if (nft != address(0)) revert(AlreadyInitialized_ERROR);
        nft = nft_;
    }

    modifier onlyNFT() {
        if (tx.origin != nft) revert(NotNFT_ERROR);
        _;
    }

    function setSeed(uint256 tokenId, bytes32 seed) external onlyNFT {
        _seeds[tokenId] = seed;
    }

    function incrementTransferCount(uint256 tokenId) external onlyNFT {
        unchecked { _txCounts[tokenId]++; }
    }

    function seedOf(uint256 tokenId) external view returns (bytes32) {
        return _seeds[tokenId];
    }

    function transferCountOf(uint256 tokenId) external view returns (uint16) {
        return _txCounts[tokenId];
    }
}