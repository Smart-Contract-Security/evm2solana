// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

/// @title IEAGWithdrawVault - Interface for the EAGWithdrawVault staking vault contract
/// @notice Defines the interface for a per-user staking vault that receives validator
///         withdrawals and execution-layer rewards. Fee management (rates, receivers,
///         claiming) is delegated to EAGVaultOperator; this vault only holds and
///         distributes ETH on command.
interface IEAGWithdrawVault {

    // ═══════════════════════════════════════════
    //              VIEW FUNCTIONS
    // ═══════════════════════════════════════════

    /// @notice Returns the EAGVaultOperator address used by this vault
    function EAGVaultOperator() external view returns (address);
    /// @notice Returns the current vault owner
    function owner() external view returns (address);
    /// @notice Returns the pending owner awaiting acceptance
    function pendingOwner() external view returns (address);
    /// @notice Returns the 0x02-type withdrawal credentials derived from this vault's address
    function withdrawalCredentials() external view returns (bytes32);
    /// @notice Returns the withdrawable balance (vault ETH minus accrued fees)
    function availableBalance() external view returns (uint256);
    /// @notice Returns the current ETH balance held by this vault
    function balanceOf() external view returns (uint256);
    /// @notice Returns the pending owner balance available for pull-based withdrawal
    function pendingOwnerBalance() external view returns (uint256);

    /// @notice Returns the vault's current ETH balance together with the pending
    ///         owner balance in a single STATICCALL.
    /// @dev Combined accessor designed for oracle reconciliation hot paths
    ///      (e.g. `EAGVaultOperator.updateVaultData`) to avoid a separate
    ///      external `BALANCE` lookup in addition to `pendingOwnerBalance()`.
    ///      Internally uses `SELFBALANCE` (5 gas) + one `SLOAD`, saving ~100
    ///      gas per vault vs. calling `pendingOwnerBalance()` and then reading
    ///      `vault.balance` from the caller.
    /// @return balance        The vault's current ETH balance (`address(this).balance`)
    /// @return pendingBalance The pull-based owner balance (`_pendingOwnerBalance`)
    function reconcileState() external view returns (uint256 balance, uint256 pendingBalance);

    // ═══════════════════════════════════════════
    //              INITIALIZATION
    // ═══════════════════════════════════════════

    /// @notice One-time initialization called by EAGVaultFactory during deployment
    /// @dev Callable by: EAGVaultFactory only | Checks: not already initialized, non-zero args
    /// @param _owner Initial vault owner
    /// @param _vaultOperator EAGVaultOperator contract address
    function initialize(address _owner, address _vaultOperator) external;

    // ═══════════════════════════════════════════
    //       VAULT OPERATOR OPERATIONS
    // ═══════════════════════════════════════════

    /// @notice Trigger a validator withdrawal via EIP-7002 (full exit or partial)
    /// @dev Callable by: EAGVaultOperator only | Checks: msg.value >= fee, validator activated
    /// @param _pubkey The 48-byte BLS public key of the validator
    /// @param _amountInGwei Withdrawal amount in Gwei (0 = full exit)
    /// @param _excessRefundRecipient Address to receive excess ETH beyond the required fee
    function triggerValidatorWithdrawal(
        bytes calldata _pubkey,
        uint64 _amountInGwei,
        address _excessRefundRecipient
    ) external payable;

    /// @notice Distribute all vault funds: fees to receivers, remainder to owner
    /// @dev Callable by: EAGVaultOperator only | Checks: sufficient balance for fees
    function claimAll() external;

    /// @notice Withdraw accumulated owner balance when direct transfer was deferred
    /// @dev Callable by: owner only | Checks: pending balance > 0
    function withdrawOwnerBalance() external;

    // ═══════════════════════════════════════════
    //           OWNER OPERATIONS
    // ═══════════════════════════════════════════

    /// @notice Initiate a two-step ownership transfer
    /// @dev Callable by: owner only | Checks: non-zero new owner
    /// @param _newOwner Address of the new pending owner
    function transferOwnership(address _newOwner) external;

    /// @notice Accept the pending ownership transfer
    /// @dev Callable by: pending owner only
    function acceptOwnership() external;

    /// @notice Cancel a pending ownership transfer
    /// @dev Callable by: owner only
    function cancelOwnershipTransfer() external;

    /// @notice Renounce ownership (intentionally disabled for safety, always reverts)
    /// @dev Callable by: owner only, always reverts
    function renounceOwnership() external view;

    /// @notice Recover accidentally sent ERC20 tokens (native ETH is prohibited)
    /// @dev Callable by: owner only | Checks: non-zero args, not native ETH sentinel
    /// @param _token The ERC20 token contract address
    /// @param _recipient Address to receive the recovered tokens
    /// @param _amount Amount of tokens to recover
    function collectERC20(address _token, address _recipient, uint256 _amount) external;

    // ═══════════════════════════════════════════
    //                 EVENTS
    // ═══════════════════════════════════════════

    /// @notice Emitted when the vault is initialized
    event VaultInitialized(address indexed owner, address indexed vaultOperator);
    /// @notice Emitted when a full validator exit is triggered via EIP-7002
    event ValidatorFullExitTriggered(bytes32 indexed pubkeyHash, bytes pubkey);
    /// @notice Emitted when a partial validator withdrawal is triggered via EIP-7002
    event ValidatorPartialWithdrawalTriggered(bytes32 indexed pubkeyHash, bytes pubkey, uint256 amountWei);
    /// @notice Emitted when all vault funds are claimed and distributed
    event VaultClaimedAll(uint256 userAmount, uint256 serviceFeeAmount, uint256 contributionFeeAmount);
    /// @notice Emitted when a two-step ownership transfer is initiated
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    /// @notice Emitted when ownership transfer is completed
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    /// @notice Emitted when a pending ownership transfer is canceled
    event OwnershipTransferCanceled(address indexed previousOwner);
    /// @notice Emitted when a fee transfer fails
    event FeeTransferFailed(address indexed recipient, uint256 amount);
    /// @notice Emitted when owner ETH transfer in claimAll was deferred to pending balance
    event OwnerTransferDeferred(address indexed owner, uint256 amount);
    /// @notice Emitted when the vault owner pulls their deferred balance
    event OwnerBalanceWithdrawn(address indexed owner, uint256 amount);
}
