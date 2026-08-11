// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { OwnableBasic } from "@limitbreak/creator-token-standards/src/access/OwnableBasic.sol";
import { IHeraldia } from "./interfaces/IHeraldia.sol";
import { IHeraldiaStorage } from "./interfaces/IHeraldiaStorage.sol";

contract HeraldiaArtSelectionV2 is OwnableBasic {

    // ─── Errors ───────────────────────────────────────────────
    error NotTokenOwner();
    error InvalidHash();
    error InvalidTransfersAllowed();

    // ─── Events ───────────────────────────────────────────────
    event ArtSelected(
        uint256 indexed tokenId,
        address indexed selectedBy,
        bytes32 customHash,
        uint8 transfersAllowed,
        uint256 artTimestamp
    );
    event ArtReset(uint256 indexed tokenId);

    // ─── Storage ──────────────────────────────────────────────
    struct SelectionData {
        bytes32 customHash;
        address selectedBy;
        bool isActive;
        uint8 transfersAllowed;          // 1–16
        uint256 activationTransferCount; // transferCount
        uint256 artTimestamp;          // timestamp
    }

    IHeraldia public heraldiaContract;
    IHeraldiaStorage public storageContract;

    mapping(uint256 => SelectionData) private _selections;

    constructor(IHeraldia _heraldia, IHeraldiaStorage _storage) OwnableBasic() {
        heraldiaContract = IHeraldia(_heraldia);
        storageContract = IHeraldiaStorage(_storage);
    }

    function selectArt(
        uint256 tokenId,
        bytes32 customHash,
        uint8 transfersAllowed,
        uint256 artTimestamp
    ) external {
        if (heraldiaContract.ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        if (customHash == bytes32(0)) revert InvalidHash();
        if (transfersAllowed < 1 || transfersAllowed > 16) revert InvalidTransfersAllowed();

        uint256 currentTransferCount = storageContract.getTransferCount(tokenId);

        _selections[tokenId] = SelectionData({
            customHash: customHash,
            selectedBy: msg.sender,
            isActive: true,
            transfersAllowed: transfersAllowed,
            activationTransferCount: currentTransferCount,
            artTimestamp: artTimestamp
        });

        emit ArtSelected(tokenId, msg.sender, customHash, transfersAllowed, artTimestamp);
    }

    function resetArt(uint256 tokenId) external {
        if (heraldiaContract.ownerOf(tokenId) != msg.sender) revert NotTokenOwner();

        delete _selections[tokenId];

        emit ArtReset(tokenId);
    }

    // ─── View ─────────────────────────────────────────────────

    function getActiveHash(uint256 tokenId) external view returns (bool isActive, bytes32 customHash) {
        SelectionData memory s = _selections[tokenId];

        if (!s.isActive) return (false, bytes32(0));

        uint256 currentTransferCount = storageContract.getTransferCount(tokenId);
        uint256 transfersSinceActivation = currentTransferCount - s.activationTransferCount;
        if (transfersSinceActivation >= s.transfersAllowed) return (false, bytes32(0));

        return (true, s.customHash);
    }

    function getSelectionData(uint256 tokenId) external view returns (
        bool isActive,
        bytes32 customHash,
        uint8 transfersAllowed,
        uint256 transfersRemaining,
        uint256 artTimestamp
    ) {
        SelectionData memory s = _selections[tokenId];

        if (!s.isActive) return (false, bytes32(0), 0, 0, 0);

        uint256 currentTransferCount = storageContract.getTransferCount(tokenId);
        uint256 transfersSinceActivation = currentTransferCount - s.activationTransferCount;

        if (transfersSinceActivation >= s.transfersAllowed) return (false, bytes32(0), 0, 0, 0);

        uint256 remaining = s.transfersAllowed - transfersSinceActivation;

        return (true, s.customHash, s.transfersAllowed, remaining, s.artTimestamp);
    }

    function hasCustomArt(uint256 tokenId) external view returns (bool) {
        (bool active,) = this.getActiveHash(tokenId);
        return active;
    }

    // ─── Admin ────────────────────────────────────────────────

    function adminSelectArt(
        uint256 tokenId,
        bytes32 customHash,
        uint8 transfersAllowed,
        uint256 artTimestamp
    ) external onlyOwner {
        if (customHash == bytes32(0)) revert InvalidHash();
        if (transfersAllowed < 1 || transfersAllowed > 16) revert InvalidTransfersAllowed();

        address currentOwner = heraldiaContract.ownerOf(tokenId);
        uint256 currentTransferCount = storageContract.getTransferCount(tokenId);

        _selections[tokenId] = SelectionData({
            customHash: customHash,
            selectedBy: currentOwner,
            isActive: true,
            transfersAllowed: transfersAllowed,
            activationTransferCount: currentTransferCount,
            artTimestamp: artTimestamp
        });

        emit ArtSelected(tokenId, currentOwner, customHash, transfersAllowed, artTimestamp);
    }

    function setHeraldiaContract(address _heraldia) external onlyOwner {
        heraldiaContract = IHeraldia(_heraldia);
    }

    function setStorageContract(address _storage) external onlyOwner {
        storageContract = IHeraldiaStorage(_storage);
    }
}
