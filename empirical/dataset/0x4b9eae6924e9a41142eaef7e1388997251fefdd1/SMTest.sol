// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Base.sol";

contract SMTest is Base {
  function internalTwo(uint256 a, uint256 b) internal pure returns (uint256) {
    return internalOne(a, b) + internalOne(a, b);
  }

  function externalOne(uint256 a, uint256 b) external pure returns (uint256) {
    return internalTwo(a, b) + internalTwo(a, b);
  }

  function externalTwo(uint256 a, uint256 b) external pure returns (uint256) {
    return internalSub(a, b);
  }
  
}