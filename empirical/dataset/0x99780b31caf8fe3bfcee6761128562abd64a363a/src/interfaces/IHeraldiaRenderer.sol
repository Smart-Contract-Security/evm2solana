// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

interface IHeraldiaRenderer {
    function tokenURI(uint256 tokenId) external view returns (string memory);
}
