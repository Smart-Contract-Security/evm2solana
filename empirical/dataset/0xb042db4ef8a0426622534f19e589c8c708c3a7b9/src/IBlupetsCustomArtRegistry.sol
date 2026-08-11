// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IBlupetsCustomArtRegistry {
    function customArt(uint256 tokenId)
        external
        view
        returns (bool active, bytes32 artKey, string memory lineage, string memory form);
}
