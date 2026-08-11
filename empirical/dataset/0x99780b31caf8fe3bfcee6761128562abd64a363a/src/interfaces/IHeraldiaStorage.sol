// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

interface IHeraldiaStorage {
    function setTokenData(
        uint256 tokenId,
        bytes32 staticHash
    ) external;

    function incrementTransferCount(uint256 tokenId) external;

    function getStaticHash(uint256 tokenId) external view returns (bytes32);

    function getTransferCount(uint256 tokenId) external view returns (uint256);

    function isTokenDataSet(uint256 tokenId) external view returns (bool);
}