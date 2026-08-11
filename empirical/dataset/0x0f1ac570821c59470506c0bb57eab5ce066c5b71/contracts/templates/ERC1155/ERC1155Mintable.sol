// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * ChainForge — ERC1155 Mintable Feature
 *
 * - Adds MINTER_ROLE gated mint + mintBatch
 * - Designed as a mixin for generated variants
 *
 * IMPORTANT:
 * - The final generated contract must inherit ERC1155Base and call ERC1155Base(uri_) in constructor.
 * - This feature assumes AccessControl is available (from ERC1155Base).
 */

import "./ERC1155Base.sol";

abstract contract ERC1155MintableFeature is ERC1155Base {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    function mint(
        address to,
        uint256 id,
        uint256 amount,
        bytes calldata data
    ) external onlyRole(MINTER_ROLE) {
        _mint(to, id, amount, data);
    }

    function mintBatch(
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata data
    ) external onlyRole(MINTER_ROLE) {
        _mintBatch(to, ids, amounts, data);
    }
}