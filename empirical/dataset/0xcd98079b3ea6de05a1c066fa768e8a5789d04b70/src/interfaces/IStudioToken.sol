// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "./IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title IStudioToken
/// @notice Soulbound governance token managed by `StudioVault`.
/// @dev Extends ERC20 metadata surface while disabling transferable behavior in implementation.
interface IStudioToken is IERC20, IERC20Metadata {
    /// @notice Raised when a privileged method is called by non-vault sender.
    error NotVault();
    /// @notice Raised when an expected non-zero address is zero.
    error ZeroAddress();
    /// @notice Raised when an expected non-zero amount is zero.
    error ZeroAmount();
    /// @notice Raised when transfer-like ERC20 methods are called.
    error SoulboundDisabled();
    /// @notice Raised when force transfer source balance is insufficient.
    error InsufficientBalance();
    /// @notice Raised when source and destination addresses match.
    error SelfTransfer();

    /// @notice Emitted when the vault forcibly moves tokens between holders.
    /// @param from Source token holder.
    /// @param to Destination token holder.
    /// @param amount Amount moved.
    event ForcedTransfer(address indexed from, address indexed to, uint256 amount);

    /// @notice Returns the vault address with mint/force-transfer permissions.
    function VAULT() external view returns (address);

    /// @notice Mints governance tokens to a recipient.
    /// @param to Recipient of minted tokens.
    /// @param amount Amount to mint.
    function mint(address to, uint256 amount) external;

    /// @notice Moves tokens between holders bypassing transfer restrictions.
    /// @param from Source holder.
    /// @param to Destination holder.
    /// @param amount Amount to move.
    function forceTransfer(address from, address to, uint256 amount) external;

    /// @notice Returns voting units at a historical block.
    /// @param account Account whose voting units are queried.
    /// @param blockNumber Historical block number.
    /// @return Voting units at `blockNumber`.
    function getPastVotes(address account, uint256 blockNumber) external view returns (uint256);

    /// @notice Returns total voting supply at a historical block.
    /// @param blockNumber Historical block number.
    /// @return Total supply at `blockNumber`.
    function getPastTotalSupply(uint256 blockNumber) external view returns (uint256);
}
