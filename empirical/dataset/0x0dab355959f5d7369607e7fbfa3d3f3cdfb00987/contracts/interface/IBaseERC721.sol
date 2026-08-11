// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IBaseERC721 is IERC721 {
    function updateBlockListStatus(address _user, bool _isBlocked) external;

    function updateTokenLockStatus(
        address _user,
        uint256 _tokenId,
        bool _isLocked
    ) external;

    function setBaseURI(string memory _newURI) external;

    function isBlocklisted(address _user) external returns (bool);

    function isWhitelisted(address _marketplace) external returns (bool);

    function isTokenLocked(uint256 _tokenId) external returns (bool);

    function updateWhitelist(
        address _marketplaceAddress,
        bool _isWhitelisted
    ) external;

    function mint(
        address _receiver,
        uint256 _itemId
    ) external returns (uint256);

    function bridgeMint(
        address _receiver,
        uint256 _tokenId,
        uint256 _itemId
    ) external;

    function batchMint(
        address[] calldata _receivers,
        uint256[] calldata _itemIds
    ) external;

    function isTokenRecentlyTransfered(
        uint256 _tokenId
    ) external returns (bool);

    function getTokenItemID(uint256 _tokenId) external view returns (uint256);

    function safeOwnerOf(uint256 _tokenId) external returns (address);
}
