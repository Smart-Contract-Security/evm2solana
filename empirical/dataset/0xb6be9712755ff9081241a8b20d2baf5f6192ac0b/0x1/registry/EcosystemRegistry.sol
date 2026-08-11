// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

import {IEcosystemRegistry} from "../interfaces/IEcosystemRegistry.sol";

contract EcosystemRegistry is Ownable2Step, IEcosystemRegistry {
    address public override tokenFactory;
    address public override nftFactory;

    address[] private _tokenList;
    address[] private _collectionList;

    mapping(address => TokenInfo) private _tokens;
    mapping(address => CollectionInfo) private _collections;

    error NotTokenFactory();
    error NotNFTFactory();
    error AlreadyRegistered();
    error AlreadyWired();
    error ZeroAddress();
    error OffsetOutOfBounds();

    constructor(address initialOwner) Ownable(initialOwner) {
        if (initialOwner == address(0)) revert ZeroAddress();
    }

    /// @notice One-shot wire-up of the TokenFactory. Reverts on subsequent calls.
    function setTokenFactory(address factory_) external onlyOwner {
        if (tokenFactory != address(0)) revert AlreadyWired();
        if (factory_ == address(0)) revert ZeroAddress();
        tokenFactory = factory_;
        emit TokenFactoryUpdated(factory_);
    }

    /// @notice One-shot wire-up of the NFTFactory. Reverts on subsequent calls.
    function setNftFactory(address factory_) external onlyOwner {
        if (nftFactory != address(0)) revert AlreadyWired();
        if (factory_ == address(0)) revert ZeroAddress();
        nftFactory = factory_;
        emit NftFactoryUpdated(factory_);
    }

    /// @inheritdoc IEcosystemRegistry
    function registerToken(
        address token,
        address creator,
        string calldata name,
        string calldata symbol,
        uint256 supply
    ) external override {
        if (msg.sender != tokenFactory) revert NotTokenFactory();
        if (_tokens[token].token != address(0)) revert AlreadyRegistered();

        _tokens[token] = TokenInfo({
            token: token,
            creator: creator,
            name: name,
            symbol: symbol,
            supply: supply,
            createdAt: uint64(block.timestamp)
        });
        _tokenList.push(token);
        emit TokenRegistered(token, creator, name, symbol, supply);
    }

    /// @inheritdoc IEcosystemRegistry
    function registerCollection(
        address collection,
        address creator,
        string calldata name,
        string calldata symbol,
        uint256 maxSupply,
        uint256 mintPrice
    ) external override {
        if (msg.sender != nftFactory) revert NotNFTFactory();
        if (_collections[collection].collection != address(0)) revert AlreadyRegistered();

        _collections[collection] = CollectionInfo({
            collection: collection,
            creator: creator,
            name: name,
            symbol: symbol,
            maxSupply: maxSupply,
            mintPrice: mintPrice,
            createdAt: uint64(block.timestamp)
        });
        _collectionList.push(collection);
        emit CollectionRegistered(collection, creator, name, symbol, maxSupply, mintPrice);
    }

    function tokenInfo(address token) external view override returns (TokenInfo memory) {
        return _tokens[token];
    }

    function collectionInfo(address collection) external view override returns (CollectionInfo memory) {
        return _collections[collection];
    }

    function totalTokens() external view override returns (uint256) {
        return _tokenList.length;
    }

    function totalCollections() external view override returns (uint256) {
        return _collectionList.length;
    }

    function getTokens(uint256 offset, uint256 limit)
        external
        view
        override
        returns (TokenInfo[] memory page)
    {
        uint256 total = _tokenList.length;
        if (offset >= total) return new TokenInfo[](0);
        uint256 end = offset + limit;
        if (end > total) end = total;
        uint256 size = end - offset;
        page = new TokenInfo[](size);
        for (uint256 i; i < size; ++i) {
            page[i] = _tokens[_tokenList[offset + i]];
        }
    }

    function getCollections(uint256 offset, uint256 limit)
        external
        view
        override
        returns (CollectionInfo[] memory page)
    {
        uint256 total = _collectionList.length;
        if (offset >= total) return new CollectionInfo[](0);
        uint256 end = offset + limit;
        if (end > total) end = total;
        uint256 size = end - offset;
        page = new CollectionInfo[](size);
        for (uint256 i; i < size; ++i) {
            page[i] = _collections[_collectionList[offset + i]];
        }
    }
}
