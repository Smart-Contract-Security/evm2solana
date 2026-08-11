// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IBlupetsCore {
    struct TokenState {
        uint8 stage;
        uint8 lineage;
        uint8 form;
        uint8 vibe;
        uint8 flags;
        uint32 parentA;
        uint32 parentB;
        uint64 updatedAt;
    }

    function ownerOf(uint256 tokenId) external view returns (address);
    function tokenState(uint256 tokenId) external view returns (TokenState memory);
    function isEngine(address engine) external view returns (bool);
    function isTokenLocked(uint256 tokenId) external view returns (bool);
    function lockToken(uint256 tokenId) external;
    function unlockToken(uint256 tokenId) external;
    function evolve(uint256 tokenId, TokenState calldata nextState) external;
    function burnForMerge(uint256 tokenId) external;
    function notifyMetadataUpdate(uint256 tokenId) external;
    function notifyBatchMetadataUpdate(uint256 fromTokenId, uint256 toTokenId) external;
}
