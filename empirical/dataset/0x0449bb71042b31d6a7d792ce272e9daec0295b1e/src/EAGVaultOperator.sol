// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import {Initializable} from "./openzeppelin/5.6/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable2StepUpgradeable} from "./openzeppelin/5.6/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ReentrancyGuardTransient} from "./openzeppelin/5.6/contracts/utils/ReentrancyGuardTransient.sol";
import {IEAGVaultOperator} from "./interfaces/IEAGVaultOperator.sol";
import {IEAGWithdrawVault} from "./interfaces/IEAGWithdrawVault.sol";
import {ErrorsLib} from "./base/ErrorsLib.sol";
import {ConstantLib} from "./base/ConstantLib.sol";

/// @title EAGVaultOperator - Centralized oracle data and fee management layer
/// @notice Stores and manages oracle-reported data and fee configuration for all
///         EAGWithdrawVault instances, indexed by vault address. Provides batch
///         management operations for rates, fee receivers, and claim settlement.
///         Does not hold any ETH or tokens.
///
///         Upgradeable via TransparentUpgradeableProxy (OZ 5.x). All persistent
///         state lives under a single ERC-7201 namespaced slot
///         (`eag.vault.operator.main`) so it cannot collide with inherited OZ
///         upgradeable modules or with future additions.
///
///         `ReentrancyGuardTransient` is safe to inherit directly (not its
///         upgradeable variant) because it uses EIP-1153 transient storage
///         (TSTORE/TLOAD) — it holds no persistent slot and therefore does not
///         participate in proxy storage layout.
contract EAGVaultOperator is
    Initializable,
    Ownable2StepUpgradeable,
    ReentrancyGuardTransient,
    IEAGVaultOperator
{
    // ═══════════════════════════════════════════
    //                VERSION
    // ═══════════════════════════════════════════

    /// @notice Human-readable implementation version. Bump on every new implementation.
    uint64 public constant VERSION = 1;

    // ═══════════════════════════════════════════
    //        ERC-7201 NAMESPACED STORAGE
    // ═══════════════════════════════════════════

    /// @custom:storage-location erc7201:eag.vault.operator.main
    struct MainStorage {
        address oracle;
        address stakingRouter;
        address EAGVaultFactory;
        address feeOperator;
        uint256 maxVaultBatchSize;
        mapping(address => VaultData) vaultData;
        mapping(address => bool) initializedVaults;
        /// @dev Global, permanent pubkey registration ledger. Defense-in-depth guard that
        ///      prevents any pubkey from being re-registered across vaults — even if the
        ///      authorized StakingRouter is later replaced via `setStakingRouter` and loses
        ///      its own per-router duplicate bookkeeping. Never cleared on exit; the contract
        ///      treats validator lifecycle (activation / exit / re-deposit) as a beacon-chain
        ///      concern outside its scope.
        mapping(bytes32 => bool) globalActivatedPubkey;
    }

    /// @dev keccak256(abi.encode(uint256(keccak256("eag.vault.operator.main")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant MAIN_STORAGE_SLOT =
        0x82d2907533b7cfda1f12814615f864d825d7b0e5f8fb922aa3d97ab59315c500;

    function _storage() private pure returns (MainStorage storage $) {
        assembly {
            $.slot := MAIN_STORAGE_SLOT
        }
    }

    // ═══════════════════════════════════════════
    //                MODIFIERS
    // ═══════════════════════════════════════════

    modifier onlyOracle() {
        require(msg.sender == _storage().oracle, ErrorsLib.SenderNotOracle());
        _;
    }

    modifier onlyStakingRouter() {
        require(msg.sender == _storage().stakingRouter, ErrorsLib.SenderNotStakingRouter());
        _;
    }

    modifier onlyVaultFactory() {
        require(msg.sender == _storage().EAGVaultFactory, ErrorsLib.SenderNotVaultFactory());
        _;
    }

    modifier onlyFeeOperator() {
        require(msg.sender == _storage().feeOperator, ErrorsLib.SenderNotFeeOperator());
        _;
    }

    // ═══════════════════════════════════════════
    //               CONSTRUCTOR
    // ═══════════════════════════════════════════

    /// @notice Implementation constructor. Locks the implementation contract.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ═══════════════════════════════════════════
    //              INITIALIZER
    // ═══════════════════════════════════════════

    /// @notice One-time proxy initializer. Mirrors the legacy constructor arguments.
    /// @param owner_ The initial owner address (admin, can manage all roles)
    /// @param oracle_ The initial oracle address (can submit vault data reports)
    /// @param EAGVaultFactory_ The EAGVaultFactory contract address
    /// @param feeOperator_ The fee operator address (manages contribution fee settings)
    /// @param maxVaultBatchSize_ Max number of vaults per batched operation
    function initialize(
        address owner_,
        address oracle_,
        address EAGVaultFactory_,
        address feeOperator_,
        uint256 maxVaultBatchSize_
    ) external initializer {
        require(owner_ != address(0), ErrorsLib.ZeroArgument("_owner"));
        require(oracle_ != address(0), ErrorsLib.ZeroArgument("_oracle"));
        require(EAGVaultFactory_ != address(0), ErrorsLib.ZeroArgument("_EAGVaultFactory"));
        require(feeOperator_ != address(0), ErrorsLib.ZeroArgument("_feeOperator"));
        require(maxVaultBatchSize_ > 0, ErrorsLib.ZeroArgument("_maxVaultBatchSize"));

        __Ownable_init(owner_);
        __Ownable2Step_init();

        MainStorage storage $ = _storage();
        $.oracle = oracle_;
        $.EAGVaultFactory = EAGVaultFactory_;
        $.feeOperator = feeOperator_;
        $.maxVaultBatchSize = maxVaultBatchSize_;
    }

    // ═══════════════════════════════════════════
    //             VIEW FUNCTIONS
    // ═══════════════════════════════════════════

    /// @inheritdoc IEAGVaultOperator
    function oracle() external view returns (address) {
        return _storage().oracle;
    }

    /// @inheritdoc IEAGVaultOperator
    function stakingRouter() external view returns (address) {
        return _storage().stakingRouter;
    }

    /// @inheritdoc IEAGVaultOperator
    function EAGVaultFactory() external view returns (address) {
        return _storage().EAGVaultFactory;
    }

    /// @inheritdoc IEAGVaultOperator
    function feeOperator() external view returns (address) {
        return _storage().feeOperator;
    }

    /// @inheritdoc IEAGVaultOperator
    function maxVaultBatchSize() external view returns (uint256) {
        return _storage().maxVaultBatchSize;
    }

    /// @inheritdoc IEAGVaultOperator
    function getVaultData(address _vault) external view returns (VaultData memory) {
        return _storage().vaultData[_vault];
    }

    /// @inheritdoc IEAGVaultOperator
    function getVaultDataTimestamp(address _vault) external view returns (uint256) {
        return _storage().vaultData[_vault].reportTimestamp;
    }

    /// @inheritdoc IEAGVaultOperator
    function isValidatorRegisteredGlobally(bytes32 _pubkeyHash) external view returns (bool) {
        return _storage().globalActivatedPubkey[_pubkeyHash];
    }

    // ═══════════════════════════════════════════
    //      STAKING ROUTER: WRITE FUNCTIONS
    // ═══════════════════════════════════════════

    /// @inheritdoc IEAGVaultOperator
    function registerValidator(
        bytes32 _pubkeyHash,
        address _vault,
        uint256 _depositedAmount
    ) external onlyStakingRouter {
        MainStorage storage $ = _storage();
        require(!$.globalActivatedPubkey[_pubkeyHash], ErrorsLib.ValidatorAlreadyRegisteredGlobally(_pubkeyHash));
        require(_isRealVault(_vault), ErrorsLib.InvalidVault(_vault));
        $.globalActivatedPubkey[_pubkeyHash] = true;

        emit ValidatorRegistered(_vault, _pubkeyHash, _depositedAmount);
    }

    /// @inheritdoc IEAGVaultOperator
    function initializeVaultData(
        address _vault,
        uint16 _initServiceRate,
        uint16 _initContributionRate,
        address _serviceFeeReceiver,
        address _contributionFeeReceiver
    ) external onlyVaultFactory nonReentrant {
        MainStorage storage $ = _storage();
        require(!$.initializedVaults[_vault], ErrorsLib.VaultAlreadyInitialized());
        require(_initServiceRate >= ConstantLib.MIN_SERVICE_RATE, ErrorsLib.InvalidRate(_vault, _initServiceRate, _initContributionRate));
        require(_initContributionRate >= ConstantLib.MIN_CONTRIBUTION_RATE, ErrorsLib.InvalidRate(_vault, _initServiceRate, _initContributionRate));
        require(
            _initServiceRate + _initContributionRate <= ConstantLib.TOTAL_BASIS_POINTS,
            ErrorsLib.InvalidRate(_vault, _initServiceRate, _initContributionRate)
        );
        $.initializedVaults[_vault] = true;
        VaultData storage data = $.vaultData[_vault];
        data.serviceRate = _initServiceRate;
        data.contributionRate = _initContributionRate;
        data.serviceFeeReceiver = _serviceFeeReceiver;
        data.contributionFeeReceiver = _contributionFeeReceiver;
        emit VaultDataInitialized(_vault, _initServiceRate, _initContributionRate, _serviceFeeReceiver, _contributionFeeReceiver);
    }

    // ═══════════════════════════════════════════
    //        ORACLE: BATCH DATA UPDATE
    // ═══════════════════════════════════════════

    /// @inheritdoc IEAGVaultOperator
    function updateVaultData(OracleReportParam[] calldata _reportParams) external onlyOracle nonReentrant {
        uint256 vaultLen = _reportParams.length;
        require(vaultLen > 0, ErrorsLib.ZeroArgument("_reportParams"));
        MainStorage storage $ = _storage();
        require(vaultLen <= $.maxVaultBatchSize, ErrorsLib.BatchTooLarge());

        address prevVault = address(0);

        for (uint256 i = 0; i < vaultLen; ) {
            OracleReportParam calldata vp = _reportParams[i];
            address vault = vp.vault;

            require($.initializedVaults[vault], ErrorsLib.InvalidVault(vault));
            _requireStrictlyAscending(vault, prevVault);
            prevVault = vault;

            VaultData storage data = $.vaultData[vault];

            uint256 ts = vp.reportTimestamp;
            uint256 batchRewards = vp.batchRewards;
            uint256 batchWithdrawn = vp.batchWithdrawnPrincipalAmount;

            require(ts > data.reportTimestamp, ErrorsLib.StaleReport(vault));
            require(ts <= block.timestamp, ErrorsLib.FutureTimestamp(vault));

            uint256 newAccruedRewards = data.accruedRewards + batchRewards;
            uint256 newAccruedWithdrawn = data.accruedWithdrawnPrincipalAmount + batchWithdrawn;

            data.accruedRewards = newAccruedRewards;
            data.accruedWithdrawnPrincipalAmount = newAccruedWithdrawn;
            data.totalPrincipalAmount = vp.currentTotalPrincipalAmount;
            data.totalClBalance = vp.currentTotalClBalance;
            data.accruedOnNodeClRewards = vp.currentOnNodeClRewards;
            data.reportTimestamp = uint64(ts);

            uint256 totalAccruedInVault = newAccruedRewards + newAccruedWithdrawn;
            (uint256 vaultBalance, uint256 reservedBalance) = IEAGWithdrawVault(vault).reconcileState();
            require(
                totalAccruedInVault + reservedBalance <= vaultBalance,
                ErrorsLib.ReportedAmountExceedsVaultBalance(vault, totalAccruedInVault, reservedBalance, vaultBalance)
            );

            if (batchRewards > 0) {
                uint256 batchServiceFee = (batchRewards * data.serviceRate) / ConstantLib.TOTAL_BASIS_POINTS;
                uint256 batchContributionFee = (batchRewards * data.contributionRate) / ConstantLib.TOTAL_BASIS_POINTS;
                data.accruedServiceFeeAmount += batchServiceFee;
                data.accruedContributionFeeAmount += batchContributionFee;
            }

            emit VaultDataUpdated(
                vault,
                vp.currentTotalClBalance,
                vp.currentOnNodeClRewards,
                batchRewards,
                batchWithdrawn
            );

            unchecked { ++i; }
        }
    }

    // ═══════════════════════════════════════════
    //            CLAIM OPERATIONS
    // ═══════════════════════════════════════════

    /// @inheritdoc IEAGVaultOperator
    function claimVault(address _vault) external nonReentrant {
        require(_isRealVault(_vault), ErrorsLib.InvalidVault(_vault));
        address vaultOwner = IEAGWithdrawVault(_vault).owner();
        require(
            msg.sender == _storage().feeOperator || msg.sender == vaultOwner,
            ErrorsLib.SenderNotAuthorized()
        );
        _settleVault(_vault);
    }

    /// @inheritdoc IEAGVaultOperator
    function claimAllVaults(address[] calldata _vaults) external onlyFeeOperator nonReentrant {
        require(_vaults.length > 0, ErrorsLib.ZeroArgument("_vaults"));
        MainStorage storage $ = _storage();
        require(_vaults.length <= $.maxVaultBatchSize, ErrorsLib.BatchTooLarge());
        address prevVault = address(0);
        for (uint256 i = 0; i < _vaults.length; ) {
            require(_isRealVault(_vaults[i]), ErrorsLib.InvalidVault(_vaults[i]));
            _requireStrictlyAscending(_vaults[i], prevVault);
            prevVault = _vaults[i];
            _settleVault(_vaults[i]);
            unchecked { ++i; }
        }
    }

    // ═══════════════════════════════════════════
    //         VALIDATOR WITHDRAWAL
    // ═══════════════════════════════════════════

    /// @inheritdoc IEAGVaultOperator
    function triggerValidatorWithdrawal(
        address _vault,
        bytes calldata _pubkey,
        uint64 _amountInGwei,
        address _excessRefundRecipient
    ) external payable nonReentrant {
        require(_isRealVault(_vault), ErrorsLib.InvalidVault(_vault));
        require(msg.sender == IEAGWithdrawVault(_vault).owner(), ErrorsLib.SenderNotAuthorized());

        bytes32 pubkeyHash = keccak256(_pubkey);
        require(_storage().globalActivatedPubkey[pubkeyHash], ErrorsLib.ValidatorStatusError());

        IEAGWithdrawVault(_vault).triggerValidatorWithdrawal{value: msg.value}(
            _pubkey, _amountInGwei, _excessRefundRecipient
        );
    }

    // ═══════════════════════════════════════════
    //      OWNER: BATCH VAULT MANAGEMENT
    // ═══════════════════════════════════════════

    /// @inheritdoc IEAGVaultOperator
    function setVaultServiceRate(
        address[] calldata _vaults,
        uint16[] calldata _rates
    ) external onlyOwner nonReentrant {
        require(_vaults.length > 0, ErrorsLib.ZeroArgument("_vaults"));
        MainStorage storage $ = _storage();
        require(_vaults.length <= $.maxVaultBatchSize, ErrorsLib.BatchTooLarge());
        require(
            _vaults.length == _rates.length,
            ErrorsLib.MismatchedArrayLengths(_vaults.length, _rates.length)
        );

        address prevVault = address(0);
        for (uint256 i = 0; i < _vaults.length; ) {
            require(_isRealVault(_vaults[i]), ErrorsLib.InvalidVault(_vaults[i]));
            _requireStrictlyAscending(_vaults[i], prevVault);

            VaultData storage data = $.vaultData[_vaults[i]];
            require(data.serviceRate != _rates[i], ErrorsLib.RepeatedArgument());
            require(_rates[i] >= ConstantLib.MIN_SERVICE_RATE, ErrorsLib.InvalidRate(_vaults[i], _rates[i], data.contributionRate));
            require(
                data.contributionRate + _rates[i] <= ConstantLib.TOTAL_BASIS_POINTS,
                ErrorsLib.InvalidRate(_vaults[i], _rates[i], data.contributionRate)
            );

            prevVault = _vaults[i];
            data.serviceRate = _rates[i];
            _settleVault(_vaults[i]);

            unchecked { ++i; }
        }
        emit VaultServiceRateSet(_vaults, _rates);
    }

    /// @inheritdoc IEAGVaultOperator
    function setVaultContributionRateByOwner(
        address[] calldata _vaults,
        uint16[] calldata _rates
    ) external onlyOwner nonReentrant {
        require(_vaults.length > 0, ErrorsLib.ZeroArgument("_vaults"));
        MainStorage storage $ = _storage();
        require(_vaults.length <= $.maxVaultBatchSize, ErrorsLib.BatchTooLarge());
        require(
            _vaults.length == _rates.length,
            ErrorsLib.MismatchedArrayLengths(_vaults.length, _rates.length)
        );

        address prevVault = address(0);
        for (uint256 i = 0; i < _vaults.length; ) {
            require(_isRealVault(_vaults[i]), ErrorsLib.InvalidVault(_vaults[i]));
            _requireStrictlyAscending(_vaults[i], prevVault);

            VaultData storage data = $.vaultData[_vaults[i]];
            require(data.contributionRate != _rates[i], ErrorsLib.RepeatedArgument());
            require(_rates[i] >= ConstantLib.MIN_CONTRIBUTION_RATE, ErrorsLib.InvalidRate(_vaults[i], data.serviceRate, _rates[i]));
            require(
                data.serviceRate + _rates[i] <= ConstantLib.TOTAL_BASIS_POINTS,
                ErrorsLib.InvalidRate(_vaults[i], data.serviceRate, _rates[i])
            );

            prevVault = _vaults[i];
            data.contributionRate = _rates[i];
            _settleVault(_vaults[i]);

            unchecked { ++i; }
        }
        emit VaultContributionRateSetByOwner(_vaults, _rates);
    }

    /// @inheritdoc IEAGVaultOperator
    function setVaultContributionRateByVaultOwner(address _vault, uint16 _rate) external nonReentrant {
        require(_isRealVault(_vault), ErrorsLib.InvalidVault(_vault));
        require(msg.sender == IEAGWithdrawVault(_vault).owner(), ErrorsLib.SenderNotAuthorized());

        VaultData storage data = _storage().vaultData[_vault];
        require(data.contributionRate != _rate, ErrorsLib.RepeatedArgument());
        require(_rate >= ConstantLib.MIN_CONTRIBUTION_RATE, ErrorsLib.InvalidRate(_vault, data.serviceRate, _rate));
        require(
            data.serviceRate + _rate <= ConstantLib.TOTAL_BASIS_POINTS,
            ErrorsLib.InvalidRate(_vault, data.serviceRate, _rate)
        );

        data.contributionRate = _rate;
        _settleVault(_vault);
        emit VaultContributionRateSetByVaultOwner(_vault, _rate);
    }

    /// @inheritdoc IEAGVaultOperator
    function setVaultServiceFeeReceiver(
        address[] calldata _vaults,
        address[] calldata _receivers
    ) external onlyOwner nonReentrant {
        require(_vaults.length > 0, ErrorsLib.ZeroArgument("_vaults"));
        MainStorage storage $ = _storage();
        require(_vaults.length <= $.maxVaultBatchSize, ErrorsLib.BatchTooLarge());
        require(
            _vaults.length == _receivers.length,
            ErrorsLib.MismatchedArrayLengths(_vaults.length, _receivers.length)
        );

        address prevVault = address(0);
        for (uint256 i = 0; i < _vaults.length; ) {
            require(_isRealVault(_vaults[i]), ErrorsLib.InvalidVault(_vaults[i]));
            _requireStrictlyAscending(_vaults[i], prevVault);
            require(_receivers[i] != address(0), ErrorsLib.ZeroArgument("_receivers"));

            VaultData storage data = $.vaultData[_vaults[i]];
            require(data.serviceFeeReceiver != _receivers[i], ErrorsLib.RepeatedArgument());

            prevVault = _vaults[i];
            data.serviceFeeReceiver = _receivers[i];
            _settleVault(_vaults[i]);

            unchecked { ++i; }
        }
        emit BatchServiceFeeReceiverSet(_vaults, _receivers);
    }

    /// @inheritdoc IEAGVaultOperator
    function setVaultContributionFeeReceiver(
        address[] calldata _vaults,
        address[] calldata _receivers
    ) external onlyOwner nonReentrant {
        require(_vaults.length > 0, ErrorsLib.ZeroArgument("_vaults"));
        MainStorage storage $ = _storage();
        require(_vaults.length <= $.maxVaultBatchSize, ErrorsLib.BatchTooLarge());
        require(
            _vaults.length == _receivers.length,
            ErrorsLib.MismatchedArrayLengths(_vaults.length, _receivers.length)
        );

        address prevVault = address(0);
        for (uint256 i = 0; i < _vaults.length; ) {
            require(_isRealVault(_vaults[i]), ErrorsLib.InvalidVault(_vaults[i]));
            _requireStrictlyAscending(_vaults[i], prevVault);
            require(_receivers[i] != address(0), ErrorsLib.ZeroArgument("_receivers"));

            VaultData storage data = $.vaultData[_vaults[i]];
            require(data.contributionFeeReceiver != _receivers[i], ErrorsLib.RepeatedArgument());

            prevVault = _vaults[i];
            data.contributionFeeReceiver = _receivers[i];
            _settleVault(_vaults[i]);

            unchecked { ++i; }
        }
        emit BatchContributionFeeReceiverSet(_vaults, _receivers);
    }

    // ═══════════════════════════════════════════
    //       OWNER: ROLE MANAGEMENT
    // ═══════════════════════════════════════════

    /// @inheritdoc IEAGVaultOperator
    function setOracle(address oracle_) external onlyOwner {
        require(oracle_ != address(0), ErrorsLib.ZeroArgument("_oracle"));
        MainStorage storage $ = _storage();
        require(oracle_ != $.oracle, ErrorsLib.RepeatedArgument());
        $.oracle = oracle_;
        emit OracleChanged(oracle_);
    }

    /// @inheritdoc IEAGVaultOperator
    function setFeeOperator(address feeOperator_) external onlyOwner {
        require(feeOperator_ != address(0), ErrorsLib.ZeroArgument("_feeOperator"));
        MainStorage storage $ = _storage();
        require(feeOperator_ != $.feeOperator, ErrorsLib.RepeatedArgument());
        $.feeOperator = feeOperator_;
        emit FeeOperatorChanged(feeOperator_);
    }

    /// @inheritdoc IEAGVaultOperator
    function setMaxVaultBatchSize(uint256 maxVaultBatchSize_) external onlyOwner {
        require(maxVaultBatchSize_ > 0, ErrorsLib.ZeroArgument("_maxVaultBatchSize"));
        MainStorage storage $ = _storage();
        require(maxVaultBatchSize_ != $.maxVaultBatchSize, ErrorsLib.RepeatedArgument());
        $.maxVaultBatchSize = maxVaultBatchSize_;
        emit MaxVaultBatchSizeChanged(maxVaultBatchSize_);
    }

    /// @inheritdoc IEAGVaultOperator
    function setStakingRouter(address stakingRouter_) external onlyOwner {
        require(stakingRouter_ != address(0), ErrorsLib.ZeroArgument("_stakingRouter"));
        MainStorage storage $ = _storage();
        require(stakingRouter_ != $.stakingRouter, ErrorsLib.RepeatedArgument());
        $.stakingRouter = stakingRouter_;
        emit StakingRouterChanged(stakingRouter_);
    }

    // ═══════════════════════════════════════════
    //          INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════

    /// @notice Check if an address is a legitimate, operator-initialized vault.
    /// @dev Reads the local `initializedVaults` flag instead of calling the
    ///      factory's `isRealVault()`. The factory atomically sets both
    ///      `realVaults[vault] = true` and invokes `initializeVaultData` on
    ///      this operator (which flips `initializedVaults[vault] = true`) inside
    ///      `deployVault`, so the two flags are semantically equivalent.
    ///      Keeping the check local avoids a cross-contract STATICCALL
    ///      (~2.6k cold) + a remote SLOAD (~2.1k cold) per invocation, which
    ///      is a significant saving inside batched, per-vault loops such as
    ///      `updateVaultData` / `claimAllVaults` / `setVault*`.
    /// @param _vault The address to check
    /// @return True if the vault has been initialized by the factory
    function _isRealVault(address _vault) internal view returns (bool) {
        return _storage().initializedVaults[_vault];
    }

    /// @notice Enforce strictly-ascending order for batched vault inputs
    /// @dev Batches MUST be pre-sorted by ascending address so that duplicate /
    ///      unsorted entries can be detected in O(n) without an auxiliary mapping.
    ///      Happy path performs a single comparison; the failing branch distinguishes
    ///      between duplicate and out-of-order inputs to give callers actionable errors.
    /// @param _current The current iteration's vault address
    /// @param _prev    The previous iteration's vault address (address(0) on first call)
    function _requireStrictlyAscending(address _current, address _prev) internal pure {
        if (uint160(_current) > uint160(_prev)) return;
        if (_current == _prev) revert ErrorsLib.DuplicatedVault(_current);
        revert ErrorsLib.VaultsNotSorted(_current);
    }


    /// @notice Core settlement routine used by both the standard path and the owner
    /// @dev Claim all accrued funds from the vault
    /// @param _vault The vault to settle
    function _settleVault(address _vault) internal {
        VaultData storage data = _storage().vaultData[_vault];

        bool hasBalance = data.accruedRewards > 0
            || data.accruedWithdrawnPrincipalAmount > 0
            || data.accruedServiceFeeAmount > 0
            || data.accruedContributionFeeAmount > 0;

        if (!hasBalance) return;

        IEAGWithdrawVault(_vault).claimAll();

        data.accruedRewards = 0;
        data.accruedWithdrawnPrincipalAmount = 0;
        data.accruedServiceFeeAmount = 0;
        data.accruedContributionFeeAmount = 0;
        emit VaultClaimed(_vault);
    }
}
