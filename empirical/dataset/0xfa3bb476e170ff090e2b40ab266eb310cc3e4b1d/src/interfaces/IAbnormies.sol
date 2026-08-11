// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

struct AbnormieState {
    uint16 seedNormieId;
    uint64 staticAt;
    address frozenBy;
    uint8 freezeAction;
    bool seedDeadAtFreeze;
    uint32 pairedAtCascadeIndex;
    uint32 staticAtCascadeIndex;
    uint16 cirrusCountAtFreeze;
    bool seedCustomizedAtFreeze;
    uint64 seedDeadAtBlockAtFreeze;
}

struct Cascade {
    uint64 blockNumber;
    uint16 burnedTokenId;
    uint16 freezeTargetTokenId;
    uint8 action;
    uint8 thunderSize;
}

interface IAbnormies {
    function getAbnormieState(uint256 abnormieId) external view returns (AbnormieState memory);

    function getAllCascades() external view returns (Cascade[] memory);

    function getSeedState(uint256 normieId)
        external
        view
        returns (address lastOwner, uint16 cirrus, bool customized, bool burned, bool awakened, uint256 boundAgent);

    function ownerOf(uint256 tokenId) external view returns (address);

    function firstStaticTokenId() external view returns (uint16);

    function firstStaticSet() external view returns (bool);

    function seedDeadAtBlock(uint256 normieId) external view returns (uint64);
}
