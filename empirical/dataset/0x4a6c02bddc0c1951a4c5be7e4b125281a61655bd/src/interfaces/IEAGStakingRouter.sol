// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import {IDepositContract} from "./IDepositContract.sol";

/// @title IEAGStakingRouter - Interface for the unified staking entry point
/// @notice Defines the interface for user deposits, deposit data management,
///         and global configuration of the staking system.
///         Each user gets a dedicated EAGWithdrawVault deployed via CREATE2.
interface IEAGStakingRouter {

    // ═══════════════════════════════════════════
    //                 STRUCTS
    // ═══════════════════════════════════════════

    /// @notice Pre-registered deposit data for validator activation
    /// @param pubkey Validator BLS public key (48 bytes)
    /// @param signature BLS signature over the deposit message (96 bytes)
    /// @param depositDataRoot SSZ hash tree root of the deposit data
    struct PreDepositData {
        bytes pubkey;
        bytes signature;
        bytes32 depositDataRoot;
    }

    // ═══════════════════════════════════════════
    //              VIEW FUNCTIONS
    // ═══════════════════════════════════════════

    /// @notice Returns the Beacon Chain deposit contract reference
    function DEPOSIT_CONTRACT() external view returns (IDepositContract);
    /// @notice Returns the EAGVaultFactory contract address
    function EAGVaultFactory() external view returns (address);
    /// @notice Returns the operator address responsible for deposit data management
    function operator() external view returns (address);
    /// @notice Returns the EAGVaultOperator contract address
    function vaultOperator() external view returns (address);
    /// @notice Returns the next vault index to be assigned on new user deposit
    function nextVaultIndex() external view returns (uint256);
    /// @notice Returns the maximum number of deposit data entries per addDepositData call (0 = no limit)
    function maxDepositDataCountPerCall() external view returns (uint256);
    /// @notice Returns the vault address bound to a user (zero if none)
    /// @param _user The user address to query
    function getUserVault(address _user) external view returns (address);
    /// @notice Returns the number of unused deposit data entries for a vault
    /// @param _vaultIndex The vault index to query
    function availableDepositDataCount(uint256 _vaultIndex) external view returns (uint256);

    // ═══════════════════════════════════════════
    //            USER OPERATIONS
    // ═══════════════════════════════════════════

    /// @notice Stake ETH to activate a new validator; deploys a vault for first-time users
    /// @dev Consumes one pre-registered deposit data entry per call.
    ///      If msg.value > 32 ETH, the excess tops up the newly activated validator.
    ///      Callable by: any user | Checks: whenNotPaused, nonReentrant, msg.value >= 32 ETH
    function deposit() external payable;

    /// @notice Top up an existing validator with additional ETH.
    /// @dev Callable by: any address that already owns a vault | Checks: whenNotPaused,
    ///      nonReentrant, basic deposit-amount/length sanity. The router intentionally does
    ///      NOT verify that `_pubkey` is currently active (or even ever registered) — the
    ///      protocol no longer tracks per-validator activation state. If a caller tops up an
    ///      already-exited validator the funds will be returned by the beacon chain to the
    ///      vault's withdrawal address; this is a user-side concern.
    /// @param _pubkey The 48-byte BLS public key of the target validator
    function topUp(bytes calldata _pubkey) external payable;

    // ═══════════════════════════════════════════
    //          VAULT CALLBACK
    // ═══════════════════════════════════════════

    /// @notice Synchronize the router's `userVaults` / `userVaultIndex` bookkeeping after
    ///         a vault completes a 2-step ownership transfer.
    /// @dev Callable ONLY by a real vault deployed via the EAGVaultFactory (verified through
    ///      `IEAGVaultFactory.isRealVault(msg.sender)`). The callback enforces the protocol
    ///      invariant of «one user, one vault»: the new owner MUST NOT already be bound to
    ///      another vault, otherwise the call reverts and the vault-side `acceptOwnership`
    ///      call is rolled back atomically. Reentrancy-guarded.
    /// @param _oldOwner The vault's previous owner (whose router mapping is cleared)
    /// @param _newOwner The vault's new owner (whose router mapping is populated)
    function onVaultOwnerChanged(address _oldOwner, address _newOwner) external;

    // ═══════════════════════════════════════════
    //          OPERATOR OPERATIONS
    // ═══════════════════════════════════════════

    /// @notice Add pre-registered deposit data entries for a vault with on-chain validation
    /// @dev Callable by: operator only | Checks: pubkey/signature lengths, depositDataRoot, no duplicates
    /// @param _vaultIndex The vault index to add deposit data for
    /// @param _data Array of pre-deposit data entries (pubkey, signature, depositDataRoot)
    function addDepositData(uint256 _vaultIndex, PreDepositData[] calldata _data) external;

    /// @notice Remove unused deposit data entries from the end of the queue
    /// @dev Callable by: operator only | Checks: count <= available entries
    /// @param _vaultIndex The vault index
    /// @param _count Number of entries to remove
    function removeDepositData(uint256 _vaultIndex, uint256 _count) external;

    // ═══════════════════════════════════════════
    //          OWNER (ADMIN) OPERATIONS
    // ═══════════════════════════════════════════

    /// @notice Set the operator address
    /// @dev Callable by: owner only | Checks: non-zero, not same as current
    /// @param _operator The new operator address
    function setOperator(address _operator) external;

    /// @notice Set the maximum deposit data entries per addDepositData call
    /// @dev Callable by: owner only | Checks: non-zero, not same as current
    /// @param _maxCount New limit (0 = no limit)
    function setMaxDepositDataCountPerCall(uint256 _maxCount) external;

    /// @notice Pause all deposit and topUp operations
    /// @dev Callable by: owner only | Checks: not already paused
    function pauseDeposits() external;

    /// @notice Resume deposit and topUp operations
    /// @dev Callable by: owner only | Checks: currently paused
    function resumeDeposits() external;

    /// @notice Recover ETH accidentally sent to the router (bypassing deposit/topUp).
    /// @dev Callable by: owner only | Checks: non-zero recipient and amount, balance sufficient, nonReentrant.
    ///      `deposit()` and `topUp()` forward msg.value directly to the beacon deposit contract,
    ///      so the router should never hold ETH under normal operation. This function exists to
    ///      rescue funds mistakenly transferred via `receive()` or self-destruct.
    /// @param _to Recipient address for the rescued ETH
    /// @param _amount Amount of ETH (wei) to sweep
    function sweepETH(address payable _to, uint256 _amount) external;

    // ═══════════════════════════════════════════
    //                  EVENTS
    // ═══════════════════════════════════════════

    /// @notice Emitted when a new validator is activated via deposit
    event ValidatorDeposited(address indexed user, address indexed vault, uint256 amount, bytes pubkey);
    /// @notice Emitted when an existing validator is topped up with additional ETH
    event ValidatorTopUp(address indexed user, address indexed vault, bytes pubkey, uint256 amount);
    /// @notice Emitted when deposit data entries are added for a vault
    event DepositDataAdded(uint256 indexed vaultIndex, uint256 count);
    /// @notice Emitted when deposit data entries are removed from a vault
    event DepositDataRemoved(uint256 indexed vaultIndex, uint256 count);
    /// @notice Emitted when the operator address is changed
    event OperatorChanged(address indexed newOperator);
    /// @notice Emitted when deposits are paused
    event DepositsPaused();
    /// @notice Emitted when deposits are resumed
    event DepositsResumed();
    /// @notice Emitted when the max deposit data per call limit is changed
    event MaxDepositDataCountPerCallChanged(uint256 newMaxCount);
    /// @notice Emitted when ETH held by the router is swept to a recipient by the owner
    event ETHSwept(address indexed to, uint256 amount);
    /// @notice Emitted when the router migrates `userVaults` / `userVaultIndex` records
    ///         from the previous owner to the new owner after a vault ownership transfer.
    /// @param vault The vault contract whose ownership changed (always equals `msg.sender`
    ///        of the triggering callback)
    /// @param oldOwner The previous vault owner whose router mapping has been cleared
    /// @param newOwner The new vault owner whose router mapping has been populated
    /// @param vaultIndex The vault's CREATE2 index, preserved across the transfer
    event VaultOwnerSynced(
        address indexed vault,
        address indexed oldOwner,
        address indexed newOwner,
        uint256 vaultIndex
    );
}
