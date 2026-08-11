// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "./SakazukiTabi.sol";

contract SakazukiTabiMetadata is AccessControl {
    using Strings for uint256;

    struct TypeMetadata {
        string label;
        string name;
        string description;
        string imageURL;
        string animationURLBase;
        bool isSet;
    }

    SakazukiTabi public nftContract;

    mapping(uint8 => TypeMetadata) private _typeMetadata;

    event NftContractUpdated(address indexed newNft);
    event TypeMetadataUpdated(uint8 indexed typeId);

    error InvalidAddress();
    error TypeMetadataNotSet();

    constructor(address nftContract_) {
        if (nftContract_ == address(0)) revert InvalidAddress();
        nftContract = SakazukiTabi(nftContract_);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function setNftContract(
        address newNft
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newNft == address(0)) revert InvalidAddress();
        nftContract = SakazukiTabi(newNft);
        emit NftContractUpdated(newNft);
    }

    function setTypeMetadata(
        uint8 typeId,
        string calldata label_,
        string calldata name_,
        string calldata description_,
        string calldata imageURL_,
        string calldata animationURLBase_
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _typeMetadata[typeId] = TypeMetadata({
            label: label_,
            name: name_,
            description: description_,
            imageURL: imageURL_,
            animationURLBase: animationURLBase_,
            isSet: true
        });
        emit TypeMetadataUpdated(typeId);
    }

    function getTypeMetadata(
        uint8 typeId
    ) external view returns (TypeMetadata memory) {
        return _typeMetadata[typeId];
    }

    function tokenURI(
        uint256 tokenId
    ) external view returns (string memory) {
        (uint8 typeId, uint64 mintedAt, uint64 usedAt) = nftContract.getTokenInfo(tokenId);
        TypeMetadata memory meta = _typeMetadata[typeId];
        if (!meta.isSet) revert TypeMetadataNotSet();

        string memory animationURL = string.concat(
            meta.animationURLBase,
            "?usedAt=",
            uint256(usedAt).toString(),
            "&mintedAt=",
            uint256(mintedAt).toString()
        );
        string memory usedStr = usedAt == 0 ? "Unused" : "Used";

        string memory attributes = string.concat(
            '[{"trait_type":"Type","value":"', meta.label, '"},',
            '{"trait_type":"Status","value":"', usedStr, '"}',
            usedAt == 0
                ? ""
                : string.concat(
                    ',{"display_type":"date","trait_type":"Used At","value":',
                    uint256(usedAt).toString(),
                    "}"
                ),
            "]"
        );

        string memory json = string.concat(
            '{"name":"', meta.name, ' #', tokenId.toString(), '",',
            '"description":"', meta.description, '",',
            '"image":"', meta.imageURL, '",',
            '"animation_url":"', animationURL, '",',
            '"attributes":', attributes,
            "}"
        );

        return string.concat(
            "data:application/json;base64,",
            Base64.encode(bytes(json))
        );
    }
}
