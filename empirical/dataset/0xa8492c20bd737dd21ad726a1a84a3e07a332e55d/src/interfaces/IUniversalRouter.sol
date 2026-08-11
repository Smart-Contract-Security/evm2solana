// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IUniversalRouter {
    /// @notice Executes a series of commands. Pure `payable` call; reverts on any sub-command failure.
    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external payable;
}
