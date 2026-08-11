// SPDX-License-Identifier: GPL-3.0

/// @title ErrorsLib - Consolidated error definitions for the EAG Staking Protocol
/// @notice All custom errors used across EAG staking contracts are defined here in a
///         single library to ensure consistent ABI selectors and avoid duplication.
library ErrorsLib {
    // ═══════════════════════════════════════════
    //            SHARED / GENERIC
    // ═══════════════════════════════════════════

    /// @notice A required argument is zero (address(0), 0, or empty bytes)
    error ZeroArgument(string name);
    /// @notice A setter is called with the same value already stored
    error RepeatedArgument();
    /// @notice Caller is not authorized for the requested operation
    error SenderNotAuthorized();
    /// @notice Two paired arrays have different lengths
    error MismatchedArrayLengths(uint64 expected, uint64 actual);
    /// @notice An ETH transfer via low-level call fails
    error TransferFailed(address recipient, uint64 amount);

    // ═══════════════════════════════════════════
    //            RATE / FEE
    // ═══════════════════════════════════════════

    /// @notice Combined service + contribution fee rates exceed 100 % (10 000 bps)
    error InvalidRate(address vault, uint64 serviceRate, uint64 contributionRate);

    // ═══════════════════════════════════════════
    //           STAKING ROUTER
    // ═══════════════════════════════════════════

    /// @notice Caller is not the operator
    error SenderNotOperator();
    /// @notice Deposit below the 32 ETH minimum
    error DepositBelowMinimum();
    /// @notice Deposit above the 2048 ETH maximum
    error DepositAboveMaximum();
    /// @notice Amount is not aligned to 1 Gwei
    error AmountNotGweiAligned();
    /// @notice No pre-registered deposit data available for the vault
    error InsufficientDepositData();
    /// @notice User has no vault assigned (required for topup)
    error NoVaultAssigned();
    /// @notice Contract is already paused
    error DepositsAlreadyPaused();
    /// @notice Contract is already active
    error DepositsAlreadyResumed();
    /// @notice Deposit count change does not match expected number
    error DepositCountMismatch();
    /// @notice Pubkey already registered across any vault
    error DuplicatePubkey();
    /// @notice Vault index exceeds the allowed lookahead range
    error VaultIndexOutOfRange();
    /// @notice Provided depositDataRoot does not match the recomputed value
    error InvalidDepositDataRoot();
    /// @notice Batch size exceeds the per-call limit
    error ExceedsMaxDepositDataPerCall();
    /// @notice msg.value must be exactly 32 ETH or >= 33 ETH (activation + >=1 ETH topup)
    ///         and must not exceed MAX_DEPOSIT_AMOUNT
    error InvalidDepositAmount(uint64 value);
    /// @notice Caller is not a real vault deployed by the EAGVaultFactory
    error SenderNotRealVault();
    /// @notice The vault recorded under the old owner does not match the calling vault
    /// @dev Surfaced by `onVaultOwnerChanged` when the router's `userVaults[oldOwner]`
    ///      no longer points to `msg.sender` (e.g. mapping was already updated, vault
    ///      was deployed outside the canonical deposit flow, or arguments are spoofed).
    error VaultOwnerMismatch();
    /// @notice The new owner already has a vault assigned in the router
    /// @dev Enforces the protocol invariant of «one user, one vault». A user that is
    ///      already bound to a vault MUST NOT accept ownership of a second vault.
    error NewOwnerAlreadyHasVault();

    // ═══════════════════════════════════════════
    //            VALIDATOR
    // ═══════════════════════════════════════════

    /// @notice BLS public key is not exactly 48 bytes
    error InvalidPubkeyLength();
    /// @notice BLS signature is not exactly 96 bytes
    error InvalidSignatureLength();
    /// @notice Validator is not in the expected status for the operation
    error ValidatorStatusError();

    // ═══════════════════════════════════════════
    //          WITHDRAW VAULT
    // ═══════════════════════════════════════════

    /// @notice initialize() called more than once
    error AlreadyInitialized();
    /// @notice Caller is not the vault owner
    error SenderNotOwner();
    /// @notice Caller is not the pending owner
    error SenderNotPendingOwner();
    /// @notice Caller is not the EAGVaultFactory
    error SenderNotEAGVaultFactory();
    /// @notice Caller is not the EAGVaultOperator
    error SenderNotEAGVaultOperator();
    /// @notice msg.value less than the required EIP-7002 withdrawal fee
    error InsufficientValidatorWithdrawalFee(uint64 passed, uint64 required);
    /// @notice Attempting to collect native ETH via collectERC20
    error EthCollectionNotAllowed();
    /// @notice renounceOwnership is disabled by design
    error RenouncementNotAllowed();
    /// @notice EAGVaultOperator has not been set
    error EAGVaultOperatorNotInitialized();
    /// @notice Vault balance insufficient to cover total fees during claimAll
    error InsufficientClaimableBalance(uint64 totalAmountInVault, uint64 totalFees);
    /// @notice Vault balance insufficient to cover the amount
    error InsufficientBalance(uint64 balance, uint64 amount);

    // ═══════════════════════════════════════════
    //          VAULT OPERATOR
    // ═══════════════════════════════════════════

    /// @notice Caller is not the oracle
    error SenderNotOracle();
    /// @notice Caller is not the StakingRouter
    error SenderNotStakingRouter();
    /// @notice Caller is not the Fee operator
    error SenderNotFeeOperator();
    /// @notice Caller is not the VaultFactory
    error SenderNotVaultFactory();
    /// @notice Validator pubkey already registered globally across all vaults.
    /// @dev The previous per-vault `ValidatorAlreadyRegistered` error has been retired:
    ///      with `activatedPubkeyHashes` removed, registration is gated solely by the
    ///      global ledger, so any duplicate (same vault or cross-vault) surfaces here.
    error ValidatorAlreadyRegisteredGlobally(bytes32 pubkeyHash);
    /// @notice Batch exceeds maximum allowed size
    error BatchTooLarge();
    /// @notice Vault address is not a real vault deployed by the EAGVaultFactory
    error InvalidVault(address vault);
    /// @notice Vault array is not strictly ascending by address
    /// @dev Batch inputs (e.g. `_vaults`, `_reportParams[*].vault`) MUST be sorted
    ///      in strictly ascending order by `uint160(address)` so that duplicates and
    ///      out-of-order entries can be detected in a single O(n) pass without
    ///      allocating a `mapping`/memory set.
    error VaultsNotSorted(address vault);
    /// @notice Duplicate vault address found within the same batch input
    /// @dev Triggered when a batch entry has the same address as the previous one.
    ///      Because batches are required to be strictly ascending, duplicates always
    ///      appear as adjacent equal addresses and are caught here.
    error DuplicatedVault(address vault);
    /// @notice Vault has already been initialized
    error VaultAlreadyInitialized();
    /// @notice Report timestamp is not newer than the stored one
    error StaleReport(address vault);
    /// @notice Report timestamp is in the future
    error FutureTimestamp(address vault);
    /// @notice Vault has not been initialized
    error VaultNotInitialized(address vault);
    /// @notice Reported amount exceeds the vault balance
    error ReportedAmountExceedsVaultBalance(address vault, uint64 reportedAmount, uint64 reservedBalance, uint64 vaultBalance);

    // ═══════════════════════════════════════════
    //          VAULT FACTORY
    // ═══════════════════════════════════════════

    /// @notice Caller is not the authorized deployer
    error SenderNotAuthorizedDeployer();
    /// @notice Caller is not the admin
    error SenderNotAdmin();
    /// @notice Predicted vault address already has deployed code
    error AddressAlreadyDeployed(address target);
}