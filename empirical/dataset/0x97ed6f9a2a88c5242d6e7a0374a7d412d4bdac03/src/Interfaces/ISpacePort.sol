// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ISpacePort {
    function getSpace(bytes32 spaceKey)
        external
        view
        returns (
            uint32 ownerId,
            bool destroyed,
            string memory spaceId,
            string memory metadataUri,
            string memory about,
            uint32 nextBasketIndex,
            uint32 memberIndex
        );

    function exists(bytes32 spaceKey) external view returns (bool);
    function isDestroyed(bytes32 spaceKey) external view returns (bool);
    function isMember(bytes32 spaceKey, uint32 urbitId) external view returns (bool);
    function isBanned(bytes32 spaceKey, uint32 urbitId) external view returns (bool);
    function getOwnerId() external view returns (uint32);
    function getAzimuth() external view returns (address);
}
