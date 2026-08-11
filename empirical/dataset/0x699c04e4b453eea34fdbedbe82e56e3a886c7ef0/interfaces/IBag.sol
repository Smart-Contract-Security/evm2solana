// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IBag {
    function mintBag(address to, uint256 grossDmethAmount) external returns (uint256);
}
