// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IEcosystemRegistry {
    struct TokenInfo {
        address token;
        address creator;
        string name;
        string symbol;
        uint256 supply;
        uint64 createdAt;
    }

    struct CollectionInfo {
        address collection;
        address creator;
        string name;
        string symbol;
        uint256 maxSupply;
        uint256 mintPrice;
        uint64 createdAt;
    }

    event TokenRegistered(
        address indexed token, address indexed creator, string name, string symbol, uint256 supply
    );
    event CollectionRegistered(
        address indexed collection,
        address indexed creator,
        string name,
        string symbol,
        uint256 maxSupply,
        uint256 mintPrice
    );
    event TokenFactoryUpdated(address indexed factory);
    event NftFactoryUpdated(address indexed factory);

    function registerToken(
        address token,
        address creator,
        string calldata name,
        string calldata symbol,
        uint256 supply
    ) external;

    function registerCollection(
        address collection,
        address creator,
        string calldata name,
        string calldata symbol,
        uint256 maxSupply,
        uint256 mintPrice
    ) external;

    function tokenInfo(address token) external view returns (TokenInfo memory);
    function collectionInfo(address collection) external view returns (CollectionInfo memory);

    function totalTokens() external view returns (uint256);
    function totalCollections() external view returns (uint256);

    function getTokens(uint256 offset, uint256 limit)
        external
        view
        returns (TokenInfo[] memory page);

    function getCollections(uint256 offset, uint256 limit)
        external
        view
        returns (CollectionInfo[] memory page);

    function tokenFactory() external view returns (address);
    function nftFactory() external view returns (address);
}
