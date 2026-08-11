// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

/// @title IEAGVaultFactory - Interface for deterministic CREATE2 vault deployment
/// @notice Defines the interface for deploying EAGWithdrawVault instances with predictable addresses,
///         managing the authorized deployer (StakingRouter), and configuring initial fee parameters
///         applied to newly deployed vaults.
interface IEAGVaultFactory {

    // ═══════════════════════════════════════════
    //              VIEW FUNCTIONS
    // ═══════════════════════════════════════════

    /// @notice Returns the one-time admin address (zero after deployer is set)
    function admin() external view returns (address);
    /// @notice Returns the authorized deployer (StakingRouter) address
    function authorizedDeployer() external view returns (address);
    /// @notice Check whether an address is a vault deployed by this factory
    /// @param _vault The address to check
    function isRealVault(address _vault) external view returns (bool);
    /// @notice Predict the CREATE2 deployment address for a given vault index
    /// @param _index The vault index used as CREATE2 salt
    function predictAddress(uint256 _index) external view returns (address);
    /// @notice Returns the default contribution fee receiver for newly deployed vaults
    function contributionFeeReceiver() external view returns (address);
    /// @notice Returns the default service fee receiver for newly deployed vaults
    function serviceFeeReceiver() external view returns (address);
    /// @notice Returns the default service rate in basis points for newly deployed vaults
    function serviceRate() external view returns (uint256);
    /// @notice Returns the default contribution rate in basis points for newly deployed vaults
    function contributionRate() external view returns (uint256);

    // ═══════════════════════════════════════════
    //          STATE-CHANGING FUNCTIONS
    // ═══════════════════════════════════════════

    /// @notice Deploy a new EAGWithdrawVault via CREATE2 and initialize it
    /// @dev Callable by: authorized deployer (StakingRouter) only
    /// @param _index Vault index used as CREATE2 salt
    /// @param _owner Initial vault owner
    /// @param _vaultOperator EAGVaultOperator address for the vault
    /// @return vault The deployed vault address
    function deployVault(uint256 _index, address _owner, address _vaultOperator) external returns (address vault);

    /// @notice Set the authorized deployer; admin is permanently renounced after this call
    /// @dev Callable by: admin only (one-time operation) | Checks: non-zero deployer
    /// @param _deployer The address authorized to deploy new vaults
    function setAuthorizedDeployer(address _deployer) external;

    /// @notice Update the default rates applied to newly deployed vaults
    /// @dev Callable by: owner only | Checks: combined rates <= 10000, not same as current
    /// @param _serviceRate New service rate in basis points
    /// @param _contributionRate New contribution rate in basis points
    function setInitialRates(uint16 _serviceRate, uint16 _contributionRate) external;

    /// @notice Update the default fee receiver addresses for newly deployed vaults
    /// @dev Callable by: owner only | Checks: non-zero addresses, not same as current
    /// @param _serviceFeeReceiver New default service fee receiver
    /// @param _contributionFeeReceiver New default contribution fee receiver
    function setInitialFeeReceivers(address _serviceFeeReceiver, address _contributionFeeReceiver) external;

    // ═══════════════════════════════════════════
    //                  EVENTS
    // ═══════════════════════════════════════════

    /// @notice Emitted when a new vault is deployed via CREATE2
    event VaultDeployed(uint256 indexed index, address indexed vault);
    /// @notice Emitted when the authorized deployer is set (admin permanently renounced)
    event AuthorizedDeployerSet(address indexed deployer);
    /// @notice Emitted when default initial rates are updated
    event InitialRatesChanged(uint256 indexed serviceRate, uint256 indexed contributionRate);
    /// @notice Emitted when default initial fee receivers are updated
    event InitialFeeReceiversChanged(address indexed serviceFeeReceiver, address indexed contributionFeeReceiver);
}