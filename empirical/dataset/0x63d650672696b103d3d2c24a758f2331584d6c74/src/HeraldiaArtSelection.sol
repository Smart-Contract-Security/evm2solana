// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { OwnableBasic } from "@limitbreak/creator-token-standards/src/access/OwnableBasic.sol";
import { Lifebuoy } from "solady/utils/Lifebuoy.sol";
import { IHeraldia } from "./interfaces/IHeraldia.sol";

contract HeraldiaArtSelection is OwnableBasic, Lifebuoy {

    error NotTokenOwner();
    error InvalidHash();

    event ArtSelected(uint256 indexed tokenId, address indexed selectedBy, bytes32 customHash);
    event ArtReset(uint256 indexed tokenId);

    struct SelectionData {
        bytes32 customHash;
        address selectedBy;
        bool isActive;
    }

    IHeraldia public heraldiaContract;

    mapping(uint256 => SelectionData) private _selections;

    constructor(IHeraldia _heraldia) OwnableBasic() Lifebuoy() {
        heraldiaContract = IHeraldia(_heraldia);
    }

    // ─── Holder ───────────────────────────────────────────────

    function selectArt(uint256 tokenId, bytes32 customHash) external {
        if (heraldiaContract.ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        if (customHash == bytes32(0)) revert InvalidHash();

        _selections[tokenId] = SelectionData({
            customHash: customHash,
            selectedBy: msg.sender,
            isActive: true
        });

        emit ArtSelected(tokenId, msg.sender, customHash);
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

        address currentOwner = heraldiaContract.ownerOf(tokenId);
        if (s.selectedBy != currentOwner) return (false, bytes32(0));

        return (true, s.customHash);
    }

    function hasCustomArt(uint256 tokenId) external view returns (bool) {
        SelectionData memory s = _selections[tokenId];
        if (!s.isActive) return false;
        address currentOwner = heraldiaContract.ownerOf(tokenId);
        return s.selectedBy == currentOwner;
    }

    // ─── Admin ────────────────────────────────────────────────

    function adminSelectArt(uint256 tokenId, bytes32 customHash) external onlyOwner {
        if (customHash == bytes32(0)) revert InvalidHash();

        address currentOwner = heraldiaContract.ownerOf(tokenId);

        _selections[tokenId] = SelectionData({
            customHash: customHash,
            selectedBy: currentOwner,
            isActive: true
        });

        emit ArtSelected(tokenId, currentOwner, customHash);
    }

    function setHeraldiaContract(address _heraldia) external onlyOwner {
        heraldiaContract = IHeraldia(_heraldia);
    }
}
