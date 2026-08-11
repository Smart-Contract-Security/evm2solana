// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

interface IBaseERC1155 is IERC1155 {
    function isBlocklisted(address _user) external returns (bool);

    function isWhitelisted(address _marketplace) external returns (bool);

    function updateWhitelist(
        address _marketplaceAddress,
        bool _isWhitelisted
    ) external;

    function mint(
        address _receiver,
        uint256 _itemId, // 503001 (Epic Minnow)
        uint256 _quantity
    ) external;

    function batchMint(
        address[] calldata _receivers,
        uint256[] calldata _itemIds,
        uint256[] calldata _quantities
    ) external;

    function burn(uint256 _itemId, uint256 _amount) external;

    function burn(address _from, uint256 _itemId, uint256 _amount) external;

    function activateToken(
        uint256 itemId,
        string memory tokenUri,
        uint256 tokenLimit
    ) external;

    function deactivateToken(uint256 itemId) external;

    function updateTokenUri(uint256 itemId, string memory tokenUri) external;

    function updateTokenLimit(uint256 itemId, uint256 tokenLimit) external;

    function addLockedAmount(
        address _user,
        uint256 _itemId,
        uint256 _amount
    ) external;

    function removeLockedAmount(
        address _user,
        uint256 _itemId,
        uint256 _amount
    ) external;

    function transfer(
        address _from,
        address _to,
        uint256 _itemId,
        uint256 _amount
    ) external;

    function getAvailableItemAmount(
        address _user,
        uint256 _itemId
    ) external returns (uint256);
}
