// SPDX-License-Identifier: MIT

/// @title IStrategy
/// @notice Adapter interface for external yield protocols (Aave, Compound, etc).
/// @dev Each Strategy is a separate contract that the Vault whitelists and routes funds through.
interface IStrategy {
    /// @notice Deposit `amount` of the underlying asset into the strategy.
    /// @dev Vault must approve the strategy first. Only callable by the Vault.
    function deposit(uint64 amount) external;

    /// @notice Withdraw `amount` of the underlying asset back to the Vault.
    /// @dev Returns the actual amount withdrawn (may differ due to rounding or liquidity).
    function withdraw(uint64 amount) external returns (uint64 withdrawn);

    /// @notice Withdraw the entire underlying balance back to the Vault (used for emergency exits).
    /// @dev Triggered by Vault on critical risk signals (depeg, util 75%+, TVL drop, pause).
    ///      Strategy must withdraw as much as possible without reverting on partial liquidity.
    ///      Returns the actual amount transferred to the Vault.
    function emergencyWithdraw() external returns (uint64 withdrawn);

    /// @notice Total underlying balance currently held/earning in this strategy (principal + profit).
    function balanceOf() external view returns (uint64);

    /// @notice Current APY in basis points (1e4 = 100%). On-chain spot rate, not historical.
    function currentAPY() external view returns (uint64);

    /// @notice Time required to fully exit this strategy, in seconds. 0 = instant.
    function withdrawalDelay() external view returns (uint64);

    /// @notice Unharvested profit available (balanceOf - last recorded principal).
    function harvestable() external view returns (uint64);

    /// @notice Underlying asset address (must match Vault.asset()).
    function asset() external view returns (address);

    /// @notice Vault that owns this strategy.
    function vault() external view returns (address);
}