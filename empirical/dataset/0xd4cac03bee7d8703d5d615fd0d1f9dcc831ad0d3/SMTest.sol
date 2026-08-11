// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract Base {
  function internalOne(uint256 a, uint256 b) internal returns (uint256) {
    return a + b;
  }
}

contract SMTest is Base {
  function internalTwo(uint256 a, uint256 b) internal returns (uint256) {
    return internalOne(a, b) + internalOne(a, b);
  }

  function externalOne(uint256 a, uint256 b) external returns (uint256) {
    return internalTwo(a, b) + internalTwo(a, b);
  }
}