// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract SMTest {
  function internalOne(uint256 a, uint256 b) internal returns (uint256) {
    /*
     * This is a comment

     This is another comment

     This is a third comment

     This is a fourth comment

     This is a fifth comment
     */
    return a + b;
  }

  function internalTwo(uint256 a, uint256 b) internal returns (uint256) {
    return internalOne(a, b) + internalOne(a, b);
  }

  function externalOne(uint256 a, uint256 b) external returns (uint256) {
    return internalTwo(a, b) + internalTwo(a, b);
  }
}