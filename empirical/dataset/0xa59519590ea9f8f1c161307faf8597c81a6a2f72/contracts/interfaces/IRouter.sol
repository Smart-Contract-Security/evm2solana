// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice AgentRouter mint entry used by distribution vaults (`minXaueOut` slippage guard).
interface IRouter {
    function mint(uint256 xautAmount, uint256 minXaueOut) external returns (uint256 xaueAmount);
}
