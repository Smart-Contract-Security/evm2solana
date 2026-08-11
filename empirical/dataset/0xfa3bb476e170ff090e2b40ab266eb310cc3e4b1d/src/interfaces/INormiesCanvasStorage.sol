// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

interface INormiesCanvasStorage {
    function isTransformed(uint256 tokenId) external view returns (bool);
}
