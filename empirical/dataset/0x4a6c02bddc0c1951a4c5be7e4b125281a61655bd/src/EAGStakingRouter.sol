// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import {Initializable} from "./openzeppelin/5.6/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable2StepUpgradeable} from "./openzeppelin/5.6/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {PausableUpgradeable} from "./openzeppelin/5.6/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardTransient} from "./openzeppelin/5.6/contracts/utils/ReentrancyGuardTransient.sol";

import {IEAGStakingRouter} from "./interfaces/IEAGStakingRouter.sol";
import {IEAGVaultFactory} from "./interfaces/IEAGVaultFactory.sol";
import {IDepositContract} from "./interfaces/IDepositContract.sol";
import {IEAGVaultOperator} from "./interfaces/IEAGVaultOperator.sol";
import {DepositDataLib} from "./base/DepositDataLib.sol";
import {DepositDataKeys} from "./base/DepositDataKeys.sol";
import {ErrorsLib} from "./base/ErrorsLib.sol";
import {ConstantLib} from "./base/ConstantLib.sol";

/// @title EAGStakingRouter - Unified staking entry point
/// @notice Handles user deposits to activate validators, topUp existing validators,
///         and manages pre-registered deposit data. Each user gets a dedicated
///         EAGWithdrawVault deployed via CREATE2.
///
///         Deposit data is stored via deterministic inline-assembly slots
///         (`keccak256("EAGStakingRouter.depositData") || vaultIndex || entryIndex`)
///         for gas-efficient packing (Lido SigningKeys-style). This custom slot
///         namespace is probabilistically disjoint from the ERC-7201 main-storage
///         slot below, so the two layouts co-exist safely under the same proxy.
///
///         Upgradeable via TransparentUpgradeableProxy (OZ 5.x). All canonical state
///         lives under a single ERC-7201 namespaced slot (`eag.staking.router.main`).
///         `DEPOSIT_CONTRACT` is preserved as an immutable — immutables live in the
///         implementation bytecode and are re-baked on every new implementation, so
///         upgrades remain storage-safe but every new implementation MUST be deployed
///         with the correct beacon-chain deposit contract address (enforced by the
///         deployment script via a post-deploy assertion).
contract EAGStakingRouter is
    Initializable,
    Ownable2StepUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardTransient,
    IEAGStakingRouter
{
    // ═══════════════════════════════════════════
    //                VERSION
    // ═══════════════════════════════════════════

    /// @notice Human-readable implementation version. Bump on every new implementation.
    uint64 public constant VERSION = 1;

    // ═══════════════════════════════════════════
    //                CONSTANTS
    // ═══════════════════════════════════════════

    /// @dev Storage namespace for assembly-based deposit data slots.
    ///      Kept local because it is a domain-specific storage layout identifier
    ///      rather than a shared protocol constant. Derived slots use a triplet
    ///      `keccak256(position || vaultIndex || entryIndex)` so they cannot
    ///      collide with the ERC-7201 main-storage slot below.
    bytes32 private constant DEPOSIT_DATA_POSITION = keccak256("EAGStakingRouter.depositData");

    // ═══════════════════════════════════════════
    //               IMMUTABLES
    // ═══════════════════════════════════════════

    /// @notice The Beacon Chain deposit contract
    /// @dev Immutable is safe in upgradeable contracts because it lives in the
    ///      implementation's bytecode, not storage. However, any future
    ///      implementation MUST be deployed with the same `_depositContract`
    ///      argument (the deployment script asserts equality before upgrade).
    IDepositContract public immutable DEPOSIT_CONTRACT;

    // ═══════════════════════════════════════════
    //        ERC-7201 NAMESPACED STORAGE
    // ═══════════════════════════════════════════

    /// @custom:storage-location erc7201:eag.staking.router.main
    struct MainStorage {
        address operator;
        address vaultOperator;
        address EAGVaultFactory;
        uint256 nextVaultIndex;
        uint256 maxDepositDataCountPerCall;
        mapping(address => address) userVaults;
        mapping(address => uint256) userVaultIndex;
        /// @dev Total number of deposit data entries ever written for each vault
        mapping(uint256 => uint256) vaultDepositDataCount;
        /// @dev Next unconsumed entry index for each vault (advances on deposit)
        mapping(uint256 => uint256) vaultNextDepositDataIndex;
        /// @dev Tracks registered pubkey hashes to prevent duplicates across all vaults
        mapping(bytes32 => bool) registeredPubkeys;
    }

    /// @dev keccak256(abi.encode(uint256(keccak256("eag.staking.router.main")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant MAIN_STORAGE_SLOT =
        0xc71536bfe02bf3cb23771fb6ff264d8597c69e50d4f620148e5bef834cf19300;

    function _storage() private pure returns (MainStorage storage $) {
        assembly {
            $.slot := MAIN_STORAGE_SLOT
        }
    }

    // ═══════════════════════════════════════════
    //                MODIFIERS
    // ═══════════════════════════════════════════

    /// @notice Restricts access to the operator address
    modifier onlyOperator() {
        require(msg.sender == _storage().operator, ErrorsLib.SenderNotOperator());
        _;
    }

    // ═══════════════════════════════════════════
    //               CONSTRUCTOR
    // ═══════════════════════════════════════════

    /// @notice Implementation constructor. Binds the Beacon Chain deposit contract
    ///         into immutable bytecode and locks the implementation against direct
    ///         initialization.
    /// @param _depositContract Beacon chain official deposit contract address
    /// @custom:oz-upgrades-unsafe-allow constructor state-variable-immutable
    constructor(address _depositContract) {
        require(_depositContract != address(0), ErrorsLib.ZeroArgument("_depositContract"));
        DEPOSIT_CONTRACT = IDepositContract(_depositContract);
        _disableInitializers();
    }

    // ═══════════════════════════════════════════
    //              INITIALIZER
    // ═══════════════════════════════════════════

    /// @notice One-time proxy initializer. Mirrors the non-immutable portion of the
    ///         legacy constructor arguments.
    /// @param _initEAGVaultFactory EAGVaultFactory (proxy) address
    /// @param _initOwner Admin/owner address (can configure roles, pause, transfer ownership)
    /// @param _initOperator Operator address (can manage deposit data)
    /// @param _initVaultOperator EAGVaultOperator (proxy) address
    function initialize(
        address _initEAGVaultFactory,
        address _initOwner,
        address _initOperator,
        address _initVaultOperator
    ) external initializer {
        require(_initEAGVaultFactory != address(0), ErrorsLib.ZeroArgument("_EAGVaultFactory"));
        require(_initOwner != address(0), ErrorsLib.ZeroArgument("_initOwner"));
        require(_initOperator != address(0), ErrorsLib.ZeroArgument("_operator"));
        require(_initVaultOperator != address(0), ErrorsLib.ZeroArgument("_vaultOperator"));

        __Ownable_init(_initOwner);
        __Ownable2Step_init();
        __Pausable_init();

        MainStorage storage $ = _storage();
        $.EAGVaultFactory = _initEAGVaultFactory;
        $.operator = _initOperator;
        $.vaultOperator = _initVaultOperator;
    }

    // ═══════════════════════════════════════════
    //             VIEW FUNCTIONS
    // ═══════════════════════════════════════════

    /// @inheritdoc IEAGStakingRouter
    function operator() external view returns (address) {
        return _storage().operator;
    }

    /// @inheritdoc IEAGStakingRouter
    function EAGVaultFactory() external view returns (address) {
        return _storage().EAGVaultFactory;
    }

    /// @inheritdoc IEAGStakingRouter
    function vaultOperator() external view returns (address) {
        return _storage().vaultOperator;
    }

    /// @inheritdoc IEAGStakingRouter
    function nextVaultIndex() external view returns (uint256) {
        return _storage().nextVaultIndex;
    }

    /// @inheritdoc IEAGStakingRouter
    function getUserVault(address _user) external view returns (address) {
        return _storage().userVaults[_user];
    }

    /// @inheritdoc IEAGStakingRouter
    function availableDepositDataCount(uint256 _vaultIndex) external view returns (uint256) {
        MainStorage storage $ = _storage();
        return $.vaultDepositDataCount[_vaultIndex] - $.vaultNextDepositDataIndex[_vaultIndex];
    }

    /// @inheritdoc IEAGStakingRouter
    function maxDepositDataCountPerCall() external view returns (uint256) {
        return _storage().maxDepositDataCountPerCall;
    }

    receive() external payable {}

    // ═══════════════════════════════════════════
    //           USER: DEPOSIT & TOP_UP
    // ═══════════════════════════════════════════

    /// @inheritdoc IEAGStakingRouter
    function deposit() external payable whenNotPaused nonReentrant {
        // Must be exactly 32 ETH (activation only) OR at least 33 ETH (activation + >=1 ETH topUp),
        // and never exceed the per-call max of 2048 ETH. The in-between range (32, 33) is rejected
        // because the beacon chain requires topUp >= 1 ETH and partial amounts would revert inside
        // `_topUpValidator`, producing confusing UX.
        require(
            msg.value == ConstantLib.ACTIVATION_DEPOSIT_AMOUNT
                || (msg.value >= ConstantLib.ACTIVATION_DEPOSIT_AMOUNT + ConstantLib.MIN_TOP_UP_AMOUNT
                    && msg.value <= ConstantLib.MAX_DEPOSIT_AMOUNT),
            ErrorsLib.InvalidDepositAmount(msg.value)
        );
        require(msg.value % 1 gwei == 0, ErrorsLib.AmountNotGweiAligned());

        MainStorage storage $ = _storage();
        address vaultAddr = $.userVaults[msg.sender];
        uint256 vaultIndex;

        if (vaultAddr == address(0)) {
            vaultIndex = $.nextVaultIndex;
            $.nextVaultIndex++;

            vaultAddr = IEAGVaultFactory($.EAGVaultFactory).deployVault(vaultIndex, msg.sender, $.vaultOperator);

            $.userVaults[msg.sender] = vaultAddr;
            $.userVaultIndex[msg.sender] = vaultIndex;
        } else {
            vaultIndex = $.userVaultIndex[msg.sender];
        }

        uint256 nextIdx = $.vaultNextDepositDataIndex[vaultIndex];
        require(nextIdx < $.vaultDepositDataCount[vaultIndex], ErrorsLib.InsufficientDepositData());

        (bytes memory pubkey, bytes memory signature) =
            DepositDataKeys.loadEntry(DEPOSIT_DATA_POSITION, vaultIndex, nextIdx);

        bytes32 pubkeyHash = keccak256(pubkey);
        $.vaultNextDepositDataIndex[vaultIndex] = nextIdx + 1;

        IEAGVaultOperator($.vaultOperator).registerValidator(pubkeyHash, vaultAddr, msg.value);

        uint64 depositCountBefore = _getDepositCount();

        bytes32 wc = _withdrawalCredentials(vaultAddr);
        bytes32 depositDataRoot =
            DepositDataLib.computeActivationDepositDataRoot(pubkey, ConstantLib.ACTIVATION_DEPOSIT_AMOUNT, wc, signature);

        DEPOSIT_CONTRACT.deposit{value: ConstantLib.ACTIVATION_DEPOSIT_AMOUNT}(
            pubkey, abi.encodePacked(wc), signature, depositDataRoot
        );

        uint256 topUpAmount = msg.value - ConstantLib.ACTIVATION_DEPOSIT_AMOUNT;
        if (topUpAmount > 0) {
            _topUpValidator(pubkey, topUpAmount, wc);
        }

        require(
            _getDepositCount() - depositCountBefore == (topUpAmount > 0 ? 2 : 1),
            ErrorsLib.DepositCountMismatch()
        );

        emit ValidatorDeposited(msg.sender, vaultAddr, msg.value, pubkey);
    }

    /// @inheritdoc IEAGStakingRouter
    function topUp(bytes calldata _pubkey) external payable whenNotPaused nonReentrant {
        require(msg.value != 0, ErrorsLib.ZeroArgument("msg.value"));
        require(msg.value <= ConstantLib.MAX_DEPOSIT_AMOUNT, ErrorsLib.DepositAboveMaximum());
        require(msg.value % 1 gwei == 0, ErrorsLib.AmountNotGweiAligned());
        require(_pubkey.length == ConstantLib.PUBLIC_KEY_LENGTH, ErrorsLib.InvalidPubkeyLength());

        MainStorage storage $ = _storage();
        address vaultAddr = $.userVaults[msg.sender];
        require(vaultAddr != address(0), ErrorsLib.NoVaultAssigned());

        bytes32 wc = _withdrawalCredentials(vaultAddr);
        _topUpValidator(_pubkey, msg.value, wc);

        emit ValidatorTopUp(msg.sender, vaultAddr, _pubkey, msg.value);
    }

    // ═══════════════════════════════════════════
    //          VAULT CALLBACK
    // ═══════════════════════════════════════════

    /// @inheritdoc IEAGStakingRouter
    function onVaultOwnerChanged(address _oldOwner, address _newOwner) external nonReentrant {
        require(_newOwner != address(0), ErrorsLib.ZeroArgument("_newOwner"));
        require(_oldOwner != _newOwner, ErrorsLib.RepeatedArgument());

        MainStorage storage $ = _storage();
        require(
            IEAGVaultFactory($.EAGVaultFactory).isRealVault(msg.sender),
            ErrorsLib.SenderNotRealVault()
        );
        require($.userVaults[_oldOwner] == msg.sender, ErrorsLib.VaultOwnerMismatch());
        require($.userVaults[_newOwner] == address(0), ErrorsLib.NewOwnerAlreadyHasVault());

        uint256 idx = $.userVaultIndex[_oldOwner];
        delete $.userVaults[_oldOwner];
        delete $.userVaultIndex[_oldOwner];
        $.userVaults[_newOwner] = msg.sender;
        $.userVaultIndex[_newOwner] = idx;

        emit VaultOwnerSynced(msg.sender, _oldOwner, _newOwner, idx);
    }

    // ═══════════════════════════════════════════
    //     OPERATOR: DEPOSIT DATA MANAGEMENT
    // ═══════════════════════════════════════════

    /// @inheritdoc IEAGStakingRouter
    function addDepositData(uint256 _vaultIndex, PreDepositData[] calldata _data) external onlyOperator {
        uint256 count = _data.length;
        require(count != 0, ErrorsLib.ZeroArgument("_data"));
        MainStorage storage $ = _storage();
        require(
            $.maxDepositDataCountPerCall == 0 || count <= $.maxDepositDataCountPerCall,
            ErrorsLib.ExceedsMaxDepositDataPerCall()
        );
        require(_vaultIndex <= $.nextVaultIndex + ConstantLib.MAX_DEPOSIT_DATA_AHEAD, ErrorsLib.VaultIndexOutOfRange());

        address predictedVault = IEAGVaultFactory($.EAGVaultFactory).predictAddress(_vaultIndex);
        bytes32 wc = _withdrawalCredentials(predictedVault);
        uint256 startIndex = $.vaultDepositDataCount[_vaultIndex];

        for (uint256 i = 0; i < count;) {
            require(_data[i].pubkey.length == ConstantLib.PUBLIC_KEY_LENGTH, ErrorsLib.InvalidPubkeyLength());
            require(_data[i].signature.length == ConstantLib.SIGNATURE_LENGTH, ErrorsLib.InvalidSignatureLength());

            bytes memory pubkey = _data[i].pubkey;
            bytes memory signature = _data[i].signature;

            bytes32 expectedRoot =
                DepositDataLib.computeActivationDepositDataRoot(pubkey, ConstantLib.ACTIVATION_DEPOSIT_AMOUNT, wc, signature);
            require(expectedRoot == _data[i].depositDataRoot, ErrorsLib.InvalidDepositDataRoot());

            bytes32 pubkeyHash = keccak256(pubkey);
            require(!$.registeredPubkeys[pubkeyHash], ErrorsLib.DuplicatePubkey());
            $.registeredPubkeys[pubkeyHash] = true;

            DepositDataKeys.saveEntry(DEPOSIT_DATA_POSITION, _vaultIndex, startIndex + i, pubkey, signature);

            unchecked { ++i; }
        }

        $.vaultDepositDataCount[_vaultIndex] = startIndex + count;
        emit DepositDataAdded(_vaultIndex, count);
    }

    /// @inheritdoc IEAGStakingRouter
    function removeDepositData(uint256 _vaultIndex, uint256 _count) external onlyOperator {
        require(_count != 0, ErrorsLib.ZeroArgument("_count"));
        MainStorage storage $ = _storage();
        uint256 total = $.vaultDepositDataCount[_vaultIndex];
        uint256 nextIdx = $.vaultNextDepositDataIndex[_vaultIndex];
        require(_count <= total - nextIdx, ErrorsLib.InsufficientDepositData());

        for (uint256 i = 0; i < _count;) {
            uint256 lastIdx = total - 1 - i;
            bytes memory pubkey = DepositDataKeys.loadPubkey(DEPOSIT_DATA_POSITION, _vaultIndex, lastIdx);
            delete $.registeredPubkeys[keccak256(pubkey)];
            DepositDataKeys.clearEntry(DEPOSIT_DATA_POSITION, _vaultIndex, lastIdx);
            unchecked { ++i; }
        }

        $.vaultDepositDataCount[_vaultIndex] = total - _count;
        emit DepositDataRemoved(_vaultIndex, _count);
    }

    // ═══════════════════════════════════════════
    //    OWNER: GLOBAL CONFIG MANAGEMENT
    // ═══════════════════════════════════════════

    /// @inheritdoc IEAGStakingRouter
    function setOperator(address newOperator) external onlyOwner {
        require(newOperator != address(0), ErrorsLib.ZeroArgument("_operator"));
        MainStorage storage $ = _storage();
        require(newOperator != $.operator, ErrorsLib.RepeatedArgument());
        $.operator = newOperator;
        emit OperatorChanged(newOperator);
    }

    /// @inheritdoc IEAGStakingRouter
    function setMaxDepositDataCountPerCall(uint256 _maxCount) external onlyOwner {
        MainStorage storage $ = _storage();
        require(_maxCount != $.maxDepositDataCountPerCall, ErrorsLib.RepeatedArgument());
        $.maxDepositDataCountPerCall = _maxCount;
        emit MaxDepositDataCountPerCallChanged(_maxCount);
    }

    // ═══════════════════════════════════════════
    //         OWNER: PAUSE / RESUME
    // ═══════════════════════════════════════════

    /// @inheritdoc IEAGStakingRouter
    function pauseDeposits() external onlyOwner {
        require(!paused(), ErrorsLib.DepositsAlreadyPaused());
        _pause();
        emit DepositsPaused();
    }

    /// @inheritdoc IEAGStakingRouter
    function resumeDeposits() external onlyOwner {
        require(paused(), ErrorsLib.DepositsAlreadyResumed());
        _unpause();
        emit DepositsResumed();
    }

    // ═══════════════════════════════════════════
    //          OWNER: ASSET RECOVERY
    // ═══════════════════════════════════════════

    /// @inheritdoc IEAGStakingRouter
    function sweepETH(address payable _to, uint256 _amount) external onlyOwner nonReentrant {
        require(_to != address(0), ErrorsLib.ZeroArgument("_to"));
        require(_amount > 0, ErrorsLib.ZeroArgument("_amount"));
        uint256 bal = address(this).balance;
        require(_amount <= bal, ErrorsLib.InsufficientBalance(bal, _amount));
        (bool success, ) = _to.call{value: _amount}("");
        require(success, ErrorsLib.TransferFailed(_to, _amount));
        emit ETHSwept(_to, _amount);
    }

    // ═══════════════════════════════════════════
    //          INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════

    /// @notice Read and parse the current deposit count from the Beacon deposit contract
    /// @return The deposit count as uint64
    function _getDepositCount() internal view returns (uint64) {
        bytes memory data = DEPOSIT_CONTRACT.get_deposit_count();
        uint64 count;
        for (uint256 i = 0; i < 8; i++) {
            count |= uint64(uint8(data[i])) << uint64(i * 8);
        }
        return count;
    }

    /// @notice Construct 0x02-type withdrawal credentials from a vault address
    /// @param _vault The vault contract address
    /// @return 32-byte withdrawal credentials with 0x02 prefix
    function _withdrawalCredentials(address _vault) internal pure returns (bytes32) {
        return bytes32(ConstantLib.WC_0X02_PREFIX | uint160(_vault));
    }

    /// @notice Top up a validator via zero-signature deposit
    /// @dev TopUp minimum is 1 ETH per Beacon chain rules
    /// @param _pubkey Validator BLS public key (48 bytes)
    /// @param _amount Amount to deposit in wei (must be >= 1 ETH)
    /// @param _wc Withdrawal credentials for the validator
    function _topUpValidator(bytes memory _pubkey, uint256 _amount, bytes32 _wc) internal {
        require(_amount >= ConstantLib.MIN_TOP_UP_AMOUNT, ErrorsLib.DepositBelowMinimum());
        bytes32 depositDataRoot = DepositDataLib.computeTopUpDepositDataRoot(_pubkey, _amount, _wc);
        bytes memory zeroSignature = new bytes(ConstantLib.SIGNATURE_LENGTH);
        DEPOSIT_CONTRACT.deposit{value: _amount}(
            _pubkey, abi.encodePacked(_wc), zeroSignature, depositDataRoot
        );
    }
}
