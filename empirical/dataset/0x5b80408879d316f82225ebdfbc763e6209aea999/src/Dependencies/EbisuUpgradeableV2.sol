// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.24;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../Interfaces/IEbisuAdminRegistry.sol";
/**
 * @title EbisuUpgradeableV2
 * @notice Base contract for upgradeable contracts in the Ebisu protocol
 * @dev Implements timelock mechanism for upgrades and access control
 */

abstract contract EbisuUpgradeableV2 is UUPSUpgradeable {
    // Upgrade timelock
    address public pendingImplementation;
    uint256 public upgradeProposalTime;
    uint256 public constant UPGRADE_TIMELOCK = 7 days;

    // Registry for admin access control
    IEbisuAdminRegistry internal _ebisuAdminRegistry;

    // Events
    event UpgradeProposed(address indexed implementation, uint256 proposalTime);

    // Errors
    error NotEbisuAdmin();
    error UpgradeTimelockNotElapsed();
    error NoPendingUpgrade();
    error InvalidUpgradeImplementation();

    /**
     * @notice Modifier to restrict access to ebisu admin
     */
    modifier onlyEbisuAdmin() {
        if (msg.sender != _ebisuAdminRegistry.ebisuAdmin()) revert NotEbisuAdmin();
        _;
    }

    /**
     * @notice Proposes a new implementation for upgrade
     * @dev Starts the timelock period for the upgrade. Setting to zero address cancels any pending upgrade.
     * @param _newImplementation Address of the new implementation
     */
    function proposeUpgrade(address _newImplementation) external onlyEbisuAdmin {
        pendingImplementation = _newImplementation;
        upgradeProposalTime = block.timestamp;

        emit UpgradeProposed(_newImplementation, upgradeProposalTime);
    }

    /**
     * @dev Required by the UUPSUpgradeable module
     * @dev Override to check if the upgrade is authorized through our timelock mechanism
     * @dev This function handles both authorization and execution of the upgrade
     */
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyEbisuAdmin {
        // Verify upgrade is authorized
        if (pendingImplementation == address(0)) revert NoPendingUpgrade();
        if (newImplementation != pendingImplementation) revert InvalidUpgradeImplementation();
        if (block.timestamp < upgradeProposalTime + UPGRADE_TIMELOCK) revert UpgradeTimelockNotElapsed();

        // Clear state
        pendingImplementation = address(0);
        upgradeProposalTime = 0;
    }
}
