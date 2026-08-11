// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ICheck {
    function mintCheck(address to, uint256 grossMethAmount) external returns (uint256);
}
