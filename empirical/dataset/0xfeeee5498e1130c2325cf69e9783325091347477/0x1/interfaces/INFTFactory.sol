// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface INFTFactory {
    event CollectionCreated(
        address indexed collection,
        address indexed creator,
        string name,
        string symbol,
        uint256 maxSupply,
        uint256 mintPrice
    );

    function LAUNCH_FEE() external view returns (uint256);
    function ect() external view returns (address);
    function treasury() external view returns (address);
    function registry() external view returns (address);

    function createCollection(
        string calldata name,
        string calldata symbol,
        string calldata baseURI,
        uint256 maxSupply,
        uint256 mintPrice
    ) external returns (address collection);
}
