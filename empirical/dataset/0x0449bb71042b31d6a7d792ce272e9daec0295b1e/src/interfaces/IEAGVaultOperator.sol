// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

/// @title IEAGVaultOperator - Interface for centralized oracle data and fee management
/// @notice Manages oracle-reported data for all EAGWithdrawVault instances.
///         Stores fee rates, fee receivers, and accounting data per vault.
///         Provides batch management operations and claim settlement.
interface IEAGVaultOperator {

    // ═══════════════════════════════════════════
    //                 STRUCTS
    // ═══════════════════════════════════════════

    /// @notice Complete stored data for a vault, including oracle reports and fee configuration
    /// @param totalPrincipalAmount Total principal deposited across all validators
    /// @param totalClBalance Total consensus-layer balance across all validators
    /// @param accruedOnNodeClRewards CL rewards still on-node (not yet withdrawn)
    /// @param accruedRewards Cumulative withdrawn rewards received by the vault
    /// @param accruedWithdrawnPrincipalAmount Cumulative withdrawn principal received by the vault
    /// @param accruedServiceFeeAmount Accrued service fees (in wei)
    /// @param accruedContributionFeeAmount Accrued contribution fees (in wei)
    /// @param serviceRate Service fee rate in basis points (0-10000)
    /// @param contributionRate Contribution fee rate in basis points (0-10000)
    /// @param reportTimestamp Timestamp of the most recent oracle report
    /// @param serviceFeeReceiver Address that receives service fees
    /// @param contributionFeeReceiver Address that receives contribution fees
    /// @dev slot 7: 16+16+64+160 = 256 bits，正好一个槽
    struct VaultData {
        uint256 totalPrincipalAmount;
        uint256 totalClBalance;
        uint256 accruedOnNodeClRewards;
        uint256 accruedRewards;
        uint256 accruedWithdrawnPrincipalAmount;
        uint256 accruedServiceFeeAmount;
        uint256 accruedContributionFeeAmount;
        uint16  serviceRate;
        uint16  contributionRate;
        uint64  reportTimestamp;
        address serviceFeeReceiver;
        address contributionFeeReceiver;
    }

    /// @notice Oracle report input parameters for a single vault update
    /// @param vault The vault address this report applies to
    /// @param currentTotalPrincipalAmount Current total principal amount
    /// @param currentTotalClBalance Current total CL balance
    /// @param currentOnNodeClRewards Current on-node CL rewards
    /// @param batchRewards New rewards accrued in this batch
    /// @param batchWithdrawnPrincipalAmount Principal withdrawn in this batch
    /// @param reportTimestamp Timestamp of this report (must be > last report timestamp)
    struct OracleReportParam {
        address vault;
        uint256 currentTotalPrincipalAmount;
        uint256 currentTotalClBalance;
        uint256 currentOnNodeClRewards;
        uint256 batchRewards;
        uint256 batchWithdrawnPrincipalAmount;
        uint256 reportTimestamp;
    }

    // ═══════════════════════════════════════════
    //              VIEW FUNCTIONS
    // ═══════════════════════════════════════════

    /// @notice Returns the oracle address
    function oracle() external view returns (address);
    /// @notice Returns the StakingRouter contract address
    function stakingRouter() external view returns (address);
    /// @notice Returns the EAGVaultFactory contract address
    function EAGVaultFactory() external view returns (address);
    /// @notice Returns the fee operator address
    function feeOperator() external view returns (address);
    /// @notice Returns the max vault batch size
    function maxVaultBatchSize() external view returns (uint256);
    /// @notice Returns the complete stored data for a vault
    /// @param _vault The vault address to query
    function getVaultData(address _vault) external view returns (VaultData memory);
    /// @notice Returns the timestamp of the most recent oracle report for a vault
    /// @param _vault The vault address to query
    function getVaultDataTimestamp(address _vault) external view returns (uint256);
    /// @notice Check whether a validator pubkey has ever been registered globally (any vault).
    /// @dev Defense-in-depth against router replacement: once a pubkey is registered it can
    ///      never be re-registered, even through a newly set StakingRouter.
    /// @param _pubkeyHash The keccak256 hash of the validator BLS public key
    function isValidatorRegisteredGlobally(bytes32 _pubkeyHash) external view returns (bool);

    // ═══════════════════════════════════════════
    //        STAKING ROUTER OPERATIONS
    // ═══════════════════════════════════════════

    /// @notice Register a new validator for a vault during the deposit process
    /// @dev Callable by: StakingRouter only | Checks: not duplicate, real vault
    /// @param _pubkeyHash The keccak256 hash of the validator BLS public key
    /// @param _vault The vault address
    /// @param _depositedAmount The total deposited amount in wei
    function registerValidator(bytes32 _pubkeyHash, address _vault, uint256 _depositedAmount) external;

    // ═══════════════════════════════════════════
    //        VAULT FACTORY OPERATIONS
    // ═══════════════════════════════════════════

    /// @notice Initialize vault fee data during vault deployment
    /// @dev Callable by: VaultFactory only | Checks: vault not already initialized
    /// @param _vault The vault address to initialize
    /// @param _initServiceRate Initial service rate in basis points
    /// @param _initContributionRate Initial contribution rate in basis points
    /// @param _serviceFeeReceiver Initial service fee receiver address
    /// @param _contributionFeeReceiver Initial contribution fee receiver address
    function initializeVaultData(
        address _vault,
        uint16 _initServiceRate,
        uint16 _initContributionRate,
        address _serviceFeeReceiver,
        address _contributionFeeReceiver
    ) external;

    // ═══════════════════════════════════════════
    //          ORACLE WRITE OPERATIONS
    // ═══════════════════════════════════════════

    /// @notice Batch update oracle report data for multiple vaults
    /// @dev Callable by: oracle only | Checks: strictly-ascending unique vaults, real vaults, fresh timestamps.
    ///      `_reportParams[*].vault` MUST be sorted in strictly ascending order by `uint160(address)`
    ///      and MUST NOT contain duplicates. Violations revert with `VaultsNotSorted` or
    ///      `DuplicatedVault` respectively. Caller is responsible for pre-sorting off-chain.
    /// @param _reportParams Array of oracle report parameters, pre-sorted by ascending vault address
    function updateVaultData(OracleReportParam[] calldata _reportParams) external;

    // ═══════════════════════════════════════════
    //            CLAIM OPERATIONS
    // ═══════════════════════════════════════════

    /// @notice Claim all funds from a vault (fees to receivers, remainder to vault owner)
    /// @dev Callable by: fee operator, or vault owner | Checks: real vault
    /// @param _vault The vault address to claim from
    function claimVault(address _vault) external;
    /// @notice Claim all funds from multiple vaults (fees to receivers, remainder to vault owner)
    /// @dev Callable by: feeOperator only | Checks: strictly-ascending unique vaults, real vaults.
    ///      `_vaults` MUST be sorted in strictly ascending order by `uint160(address)` and MUST NOT
    ///      contain duplicates. Violations revert with `VaultsNotSorted` / `DuplicatedVault`.
    /// @param _vaults Array of vault addresses to claim from, pre-sorted ascending
    function claimAllVaults(address[] calldata _vaults) external;

    // ═══════════════════════════════════════════
    //         VALIDATOR WITHDRAWAL
    // ═══════════════════════════════════════════

    /// @notice Trigger a validator withdrawal via the vault's EIP-7002 integration
    /// @dev Callable by: vault owner only | Checks: real vault, pubkey was registered globally.
    ///      The contract intentionally does NOT track per-vault activation status anymore, so:
    ///        * It cannot enforce that `_pubkey` is currently bound to `_vault` — the beacon
    ///          chain rejects any EIP-7002 request whose validator's withdrawal credentials
    ///          do not match the vault, which is the authoritative check.
    ///        * It cannot tell whether the validator is still active. Triggering withdrawal on
    ///          an already-exited validator simply produces a no-op request on the beacon side.
    ///      Off-chain services (oracle, indexer) are responsible for reconciling the live
    ///      "active validator count" against beacon-chain data. The on-chain "registered
    ///      pubkey" tally can be derived from `EAGStakingRouter` (consumed deposit-data
    ///      entries == validators ever registered through the protocol).
    /// @param _vault The vault address
    /// @param _pubkey The 48-byte BLS public key of the validator
    /// @param _amountInGwei Withdrawal amount in Gwei (0 = full exit)
    /// @param _excessRefundRecipient Address to receive excess ETH beyond the required fee
    function triggerValidatorWithdrawal(
        address _vault,
        bytes calldata _pubkey,
        uint64 _amountInGwei,
        address _excessRefundRecipient
    ) external payable;

    // ═══════════════════════════════════════════
    //       OWNER: BATCH RATE MANAGEMENT
    // ═══════════════════════════════════════════

    /// @notice Batch set service fee rates for multiple vaults (settles fees before applying)
    /// @dev Callable by: owner only | Checks: strictly-ascending unique vaults, real vaults, valid rates.
    ///      `_vaults` MUST be sorted in strictly ascending order by `uint160(address)` and MUST NOT
    ///      contain duplicates. Violations revert with `VaultsNotSorted` / `DuplicatedVault`.
    /// @param _vaults Array of vault addresses, pre-sorted ascending
    /// @param _rates Array of new service rates in basis points (length must match `_vaults`)
    function setVaultServiceRate(address[] calldata _vaults, uint16[] calldata _rates) external;

    /// @notice Batch set contribution fee rates for multiple vaults (settles fees before applying)
    /// @dev Callable by: owner only | Checks: strictly-ascending unique vaults, real vaults, valid rates.
    ///      `_vaults` MUST be sorted in strictly ascending order by `uint160(address)` and MUST NOT
    ///      contain duplicates. Violations revert with `VaultsNotSorted` / `DuplicatedVault`.
    /// @param _vaults Array of vault addresses, pre-sorted ascending
    /// @param _rates Array of new contribution rates in basis points (length must match `_vaults`)
    function setVaultContributionRateByOwner(address[] calldata _vaults, uint16[] calldata _rates) external;

    /// @notice Set contribution rate for a single vault by its owner (settles fees before applying)
    /// @dev Callable by: vault owner only | Checks: real vault, valid rate
    /// @param _vault The vault address
    /// @param _rate New contribution rate in basis points
    function setVaultContributionRateByVaultOwner(address _vault, uint16 _rate) external;

    // ═══════════════════════════════════════════
    //    OWNER: BATCH FEE RECEIVER MANAGEMENT
    // ═══════════════════════════════════════════

    /// @notice Batch set service fee receiver addresses for multiple vaults
    /// @dev Callable by: owner only | Checks: strictly-ascending unique vaults, real vaults, non-zero receivers.
    ///      `_vaults` MUST be sorted in strictly ascending order by `uint160(address)` and MUST NOT
    ///      contain duplicates. Violations revert with `VaultsNotSorted` / `DuplicatedVault`.
    /// @param _vaults Array of vault addresses, pre-sorted ascending
    /// @param _receivers Array of new service fee receiver addresses (length must match `_vaults`)
    function setVaultServiceFeeReceiver(address[] calldata _vaults, address[] calldata _receivers) external;

    /// @notice Batch set contribution fee receiver addresses for multiple vaults
    /// @dev Callable by: owner only | Checks: strictly-ascending unique vaults, real vaults, non-zero receivers.
    ///      `_vaults` MUST be sorted in strictly ascending order by `uint160(address)` and MUST NOT
    ///      contain duplicates. Violations revert with `VaultsNotSorted` / `DuplicatedVault`.
    /// @param _vaults Array of vault addresses, pre-sorted ascending
    /// @param _receivers Array of new contribution fee receiver addresses (length must match `_vaults`)
    function setVaultContributionFeeReceiver(address[] calldata _vaults, address[] calldata _receivers) external;

    // ═══════════════════════════════════════════
    //          OWNER: ROLE MANAGEMENT
    // ═══════════════════════════════════════════

    /// @notice Set a new oracle address
    /// @dev Callable by: owner only | Checks: non-zero
    /// @param _oracle The new oracle address
    function setOracle(address _oracle) external;

    /// @notice Set the fee operator address
    /// @dev Callable by: owner only | Checks: non-zero
    /// @param _feeOperator The new fee operator address
    function setFeeOperator(address _feeOperator) external;

    /// @notice Set the max vault batch size
    /// @dev Callable by: owner only | Checks: non-zero
    /// @param _maxVaultBatchSize The new max vault batch size
    function setMaxVaultBatchSize(uint256 _maxVaultBatchSize) external;

    /// @notice Set the StakingRouter contract address
    /// @dev Callable by: owner only | Checks: non-zero
    /// @param _stakingRouter The new StakingRouter address
    function setStakingRouter(address _stakingRouter) external;

    // ═══════════════════════════════════════════
    //                  EVENTS
    // ═══════════════════════════════════════════

    /// @notice Emitted when oracle data is updated for a vault
    event VaultDataUpdated(
        address indexed vault,
        uint256 totalClBalance,
        uint256 onNodeClRewards,
        uint256 batchRewards,
        uint256 withdrawnPrincipalAmount
    );
    /// @notice Emitted when vault fee data is initialized during deployment
    event VaultDataInitialized(
        address indexed vault,
        uint16 serviceRate,
        uint16 contributionRate,
        address serviceFeeReceiver,
        address contributionFeeReceiver
    );
    /// @notice Emitted when a new validator is registered for a vault
    event ValidatorRegistered(address indexed vault, bytes32 indexed pubkeyHash, uint256 depositedAmount);
    /// @notice Emitted when all vault funds are claimed and accounting is reset
    event VaultClaimed(address indexed vault);
    /// @notice Emitted when service rates are batch-updated
    event VaultServiceRateSet(address[] vaults, uint16[] rates);
    /// @notice Emitted when a contribution rate is set by the owner
    event VaultContributionRateSetByOwner(address[] vaults, uint16[] rates);
    /// @notice Emitted when a contribution rate is set by a vault owner
    event VaultContributionRateSetByVaultOwner(address indexed vault, uint16 rate);
    /// @notice Emitted when service fee receivers are batch-updated
    event BatchServiceFeeReceiverSet(address[] vaults, address[] receivers);
    /// @notice Emitted when contribution fee receivers are batch-updated
    event BatchContributionFeeReceiverSet(address[] vaults, address[] receivers);
    /// @notice Emitted when the oracle address is changed
    event OracleChanged(address indexed newOracle);
    /// @notice Emitted when the StakingRouter address is changed
    event StakingRouterChanged(address indexed newStakingRouter);
    /// @notice Emitted when the EAGVaultFactory address is changed
    event EAGVaultFactoryChanged(address indexed newEAGVaultFactory);
    /// @notice Emitted when the max vault batch size is changed
    event MaxVaultBatchSizeChanged(uint256 indexed newMaxVaultBatchSize);
    /// @notice Emitted when the fee operator address is changed
    event FeeOperatorChanged(address indexed newFeeOperator);
}
