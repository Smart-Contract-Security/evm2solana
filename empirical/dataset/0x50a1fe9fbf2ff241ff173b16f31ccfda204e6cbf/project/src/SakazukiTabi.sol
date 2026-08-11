// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

interface ISakazukiTabiMetadata {
    function tokenURI(uint256 tokenId) external view returns (string memory);
}

contract SakazukiTabi is ERC721, AccessControl {
    struct TokenInfo {
        uint8 typeId;
        uint64 mintedAt;
        uint64 usedAt;
    }

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant USE_ROLE = keccak256("USE_ROLE");

    ISakazukiTabiMetadata public metadataContract;

    uint256 private _nextTokenId = 1;
    uint256 private _totalMinted;

    mapping(uint8 => bool) public isTypeRegistered;
    mapping(uint8 => uint256) private _mintedByType;
    mapping(uint256 => TokenInfo) private _tokenInfo;

    uint8[] private _registeredTypeIds;

    event MetadataContractUpdated(address indexed newMetadata);
    event TypeRegistered(uint8 indexed typeId);
    event TabiMinted(address indexed to, uint256 indexed tokenId, uint8 indexed typeId);
    event TabiUsed(uint256 indexed tokenId, uint64 usedAt);

    error InvalidAddress();
    error MetadataNotSet();
    error AlreadyUsed();
    error TypeAlreadyRegistered();
    error TypeNotRegistered();

    constructor(
        string memory name_,
        string memory symbol_
    ) ERC721(name_, symbol_) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function registerType(uint8 typeId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (isTypeRegistered[typeId]) revert TypeAlreadyRegistered();
        isTypeRegistered[typeId] = true;
        _registeredTypeIds.push(typeId);
        emit TypeRegistered(typeId);
    }

    function mint(
        address to,
        uint8 typeId
    ) external onlyRole(MINTER_ROLE) returns (uint256) {
        if (!isTypeRegistered[typeId]) revert TypeNotRegistered();

        uint256 tokenId = _nextTokenId++;

        _tokenInfo[tokenId] = TokenInfo({
            typeId: typeId,
            mintedAt: uint64(block.timestamp),
            usedAt: 0
        });
        _totalMinted++;
        _mintedByType[typeId]++;

        _safeMint(to, tokenId);

        emit TabiMinted(to, tokenId, typeId);
        return tokenId;
    }

    function markAsUsed(uint256 tokenId) external onlyRole(USE_ROLE) {
        _requireOwned(tokenId);
        if (_tokenInfo[tokenId].usedAt != 0) revert AlreadyUsed();

        uint64 usedAt = uint64(block.timestamp);
        _tokenInfo[tokenId].usedAt = usedAt;

        emit TabiUsed(tokenId, usedAt);
    }

    function setMetadataContract(
        address newMetadata
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newMetadata == address(0)) revert InvalidAddress();
        metadataContract = ISakazukiTabiMetadata(newMetadata);
        emit MetadataContractUpdated(newMetadata);
    }

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        _requireOwned(tokenId);
        if (address(metadataContract) == address(0)) revert MetadataNotSet();
        return metadataContract.tokenURI(tokenId);
    }

    function getTokenInfo(
        uint256 tokenId
    ) external view returns (uint8 typeId, uint64 mintedAt, uint64 usedAt) {
        _requireOwned(tokenId);
        TokenInfo memory info = _tokenInfo[tokenId];
        return (info.typeId, info.mintedAt, info.usedAt);
    }

    function typeIdOf(uint256 tokenId) external view returns (uint8) {
        _requireOwned(tokenId);
        return _tokenInfo[tokenId].typeId;
    }

    function mintedAtOf(uint256 tokenId) external view returns (uint64) {
        _requireOwned(tokenId);
        return _tokenInfo[tokenId].mintedAt;
    }

    function usedAtOf(uint256 tokenId) external view returns (uint64) {
        _requireOwned(tokenId);
        return _tokenInfo[tokenId].usedAt;
    }

    function isUsed(uint256 tokenId) external view returns (bool) {
        _requireOwned(tokenId);
        return _tokenInfo[tokenId].usedAt != 0;
    }

    function totalSupply() external view returns (uint256) {
        return _totalMinted;
    }

    function mintedByType(uint8 typeId) external view returns (uint256) {
        return _mintedByType[typeId];
    }

    function nextTokenId() external view returns (uint256) {
        return _nextTokenId;
    }

    function getRegisteredTypeIds() external view returns (uint8[] memory) {
        return _registeredTypeIds;
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
