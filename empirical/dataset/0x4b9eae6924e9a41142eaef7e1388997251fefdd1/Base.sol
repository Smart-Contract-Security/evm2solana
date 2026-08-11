// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract Base {
  function internalOne(uint256 a, uint256 b) internal pure returns (uint256) {
    return a + b;
  }

  function internalSub(uint256 a, uint256 b) internal pure returns (uint256) {
    return a - b;
  }
}
