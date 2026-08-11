// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

interface IOperoseAdapter {
  function getBaseTokens(address defiToken) external view returns (address[] memory tokens);
  function getBaseRatios(address defiToken) external view returns (uint256[] memory ratios);
  function getBaseAmounts(address defiToken, uint256 defiAmount) external view returns (uint256[] memory baseAmounts);
  function getGrowthIndex(address defiToken) external view returns (uint256 index);

  function zapIn(address defiToken, uint256[] memory baseAmounts) external;
  function zapOut(address defiToken, uint256 defiAmount) external;
}