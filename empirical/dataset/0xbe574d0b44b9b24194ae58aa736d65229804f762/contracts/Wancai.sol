// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ERC721SeaDrop} from "seadrop/ERC721SeaDrop.sol";
import {SSTORE2} from "./SSTORE2.sol";
import {WancaiRenderer} from "./WancaiRenderer.sol";

/**
 * @title  WANCAI 万财
 * @notice 10,000 Jin Chan, fully on-chain. ERC-721A + SeaDrop minting.
 *         Rendering is delegated to a separate WancaiRenderer contract
 *         to stay under EIP-170 24KB contract size limit.
 *
 *  Architecture:
 *    Wancai           ← this contract: trait data storage + tokenURI dispatch
 *    WancaiRenderer   ← SVG fragments + dynamic JSON metadata
 *    Both deployed together; renderer address is immutable on this contract.
 *
 *  Provenance:
 *    Set once via setProvenanceHash() (parent function); locked after first mint.
 */
contract Wancai is ERC721SeaDrop {
    // ============ Constants ============
    uint256 public constant TRAITS_PER_TOKEN = 10;
    uint256 public constant TOKENS_PER_CHUNK = 2_000;
    uint256 public constant TRAIT_CHUNKS = 5;
    uint256 public constant CHUNK_BYTE_SIZE = TOKENS_PER_CHUNK * TRAITS_PER_TOKEN;

    // ============ Renderer ============
    WancaiRenderer public immutable renderer;

    // ============ Storage ============
    address[TRAIT_CHUNKS] private _traitDataPointers;
    address private _tierDataPointer;
    bool public traitDataFinalized;

    // ============ Events ============
    event TraitChunkLoaded(uint256 indexed chunkIndex);
    event TierDataLoaded();
    event TraitDataFinalized();

    // ============ Errors ============
    error InvalidChunkIndex();
    error ChunkAlreadyLoaded();
    error TraitDataLocked();
    error TraitDataIncomplete();
    error WrongChunkSize();
    error WrongTierSize();
    error NonexistentToken();

    constructor(
        string memory name_,
        string memory symbol_,
        address[] memory allowedSeaDrop,
        address renderer_
    ) ERC721SeaDrop(name_, symbol_, allowedSeaDrop) {
        renderer = WancaiRenderer(renderer_);
    }

    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }

    // ============ Admin: load trait data ============

    function loadTraitChunk(uint256 chunkIndex, bytes calldata data) external onlyOwner {
        if (traitDataFinalized) revert TraitDataLocked();
        if (chunkIndex >= TRAIT_CHUNKS) revert InvalidChunkIndex();
        if (data.length != CHUNK_BYTE_SIZE) revert WrongChunkSize();
        if (_traitDataPointers[chunkIndex] != address(0)) revert ChunkAlreadyLoaded();
        _traitDataPointers[chunkIndex] = SSTORE2.write(data);
        emit TraitChunkLoaded(chunkIndex);
    }

    function loadTierData(bytes calldata data) external onlyOwner {
        if (traitDataFinalized) revert TraitDataLocked();
        if (data.length != _maxSupply) revert WrongTierSize();
        if (_tierDataPointer != address(0)) revert ChunkAlreadyLoaded();
        _tierDataPointer = SSTORE2.write(data);
        emit TierDataLoaded();
    }

    function finalizeTraitData() external onlyOwner {
        if (_tierDataPointer == address(0)) revert TraitDataIncomplete();
        for (uint256 i = 0; i < TRAIT_CHUNKS; i++) {
            if (_traitDataPointers[i] == address(0)) revert TraitDataIncomplete();
        }
        traitDataFinalized = true;
        emit TraitDataFinalized();
    }

    // ============ Reads ============

    function _getTraits(uint256 tokenId) internal view returns (uint8[10] memory traits) {
        uint256 zeroIdx = tokenId - 1;
        uint256 chunkIdx = zeroIdx / TOKENS_PER_CHUNK;
        uint256 offsetInChunk = (zeroIdx % TOKENS_PER_CHUNK) * TRAITS_PER_TOKEN;
        bytes memory chunk = SSTORE2.read(_traitDataPointers[chunkIdx]);
        for (uint256 i = 0; i < TRAITS_PER_TOKEN; i++) {
            traits[i] = uint8(chunk[offsetInChunk + i]);
        }
    }

    function _getTier(uint256 tokenId) internal view returns (uint8) {
        return uint8(SSTORE2.read(_tierDataPointer)[tokenId - 1]);
    }

    function getTraits(uint256 tokenId) external view returns (uint8[10] memory) {
        if (!_exists(tokenId)) revert NonexistentToken();
        return _getTraits(tokenId);
    }

    function getTier(uint256 tokenId) external view returns (uint8) {
        if (!_exists(tokenId)) revert NonexistentToken();
        return _getTier(tokenId);
    }

    // ============ Token URI (delegated to renderer) ============

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (!_exists(tokenId)) revert NonexistentToken();
        return renderer.tokenURI(tokenId, _getTraits(tokenId), _getTier(tokenId));
    }
}
