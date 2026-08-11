// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice AgentRouter mint entry used by distribution vaults (`minXaueOut` slippage guard).
/// @dev Mainnet AgentRouter `mint` has no return value; do not declare `returns` here.
interface IRouter {
    function mint(uint256 xautAmount, uint256 minXaueOut) external;
}
