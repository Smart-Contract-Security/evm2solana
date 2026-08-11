// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

interface INormies {
    function ownerOf(uint256 tokenId) external view returns (address);
}
