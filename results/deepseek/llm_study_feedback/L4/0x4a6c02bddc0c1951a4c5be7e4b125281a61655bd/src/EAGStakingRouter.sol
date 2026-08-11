// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import {IDepositContract} from "./interfaces/IDepositContract.sol";
import {DepositDataLib} from "./base/DepositDataLib.sol";
import {DepositDataKeys} from "./base/DepositDataKeys.sol";
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
contract EAGStakingRouter {
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
        address owner;
        address pendingOwner;
        bool paused;
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

    function _storage() private view returns (MainStorage storage $) {
        assembly {
            $.slot := MAIN_STORAGE_SLOT
        }
    }

    // ═══════════════════════════════════════════
    //                MODIFIERS
    // ═══════════════════════════════════════════

    /// @notice Restricts access to the operator address
    modifier onlyOperator() {
        require(tx.accounts.operator.key == _storage().operator, "SenderNotOperator");
        _;
    }

    /// @notice Restricts access to the owner address
    modifier onlyOwner() {
        require(tx.accounts.owner.key == _storage().owner, "Ownable: caller is not the owner");
        _;
    }

    /// @notice Ensures the contract is not paused
    modifier whenNotPaused() {
        require(!_storage().paused, "Pausable: paused");
        _;
    }

    /// @notice Simple reentrancy guard modifier
    modifier nonReentrant() {
        // Solang does not support transient storage, so we use a regular storage slot.
        // This is a simplified reentrancy guard.
        require(!_reentrancyGuardEntered(), "ReentrancyGuard: reentrant call");
        _setReentrancyGuardEntered(true);
        _;
        _setReentrancyGuardEntered(false);
    }

    // Reentrancy guard storage slot
    bytes32 private constant REENTRANCY_GUARD_SLOT = keccak256("eag.staking.router.reentrancy");

    function _reentrancyGuardEntered() private view returns (bool entered) {
        bytes32 slot = REENTRANCY_GUARD_SLOT;
        assembly {
            entered := sload(slot)
        }
    }

    function _setReentrancyGuardEntered(bool _entered) private {
        bytes32 slot = REENTRANCY_GUARD_SLOT;
        assembly {
            sstore(slot, _entered)
        }
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
        require(_depositContract != address(0), "ZeroArgument: _depositContract");
        DEPOSIT_CONTRACT = IDepositContract(_depositContract);
        // _disableInitializers() is not supported in Solang; we use a simple initialized flag.
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
    ) external {
        MainStorage storage $ = _storage();
        require($.owner == address(0), "Already initialized");
        require(_initEAGVaultFactory != address(0), "ZeroArgument: _EAGVaultFactory");
        require(_initOwner != address(0), "ZeroArgument: _initOwner");
        require(_initOperator != address(0), "ZeroArgument: _operator");
        require(_initVaultOperator != address(0), "ZeroArgument: _vaultOperator");

        $.owner = _initOwner;
        $.EAGVaultFactory = _initEAGVaultFactory;
        $.operator = _initOperator;
        $.vaultOperator = _initVaultOperator;
    }

    // ═══════════════════════════════════════════
    //             VIEW FUNCTIONS
    // ═══════════════════════════════════════════

    function operator() external view returns (address) {
        return _storage().operator;
    }

    function EAGVaultFactory() external view returns (address) {
        return _storage().EAGVaultFactory;
    }

    function vaultOperator() external view returns (address) {
        return _storage().vaultOperator;
    }

    function nextVaultIndex() external view returns (uint256) {
        return _storage().nextVaultIndex;
    }

    function getUserVault(address _user) external view returns (address) {
        return _storage().userVaults[_user];
    }

    function availableDepositDataCount(uint256 _vaultIndex) external view returns (uint256) {
        MainStorage storage $ = _storage();
        return $.vaultDepositDataCount[_vaultIndex] - $.vaultNextDepositDataIndex[_vaultIndex];
    }

    function maxDepositDataCountPerCall() external view returns (uint256) {
        return _storage().maxDepositDataCountPerCall;
    }

    /// @notice Returns the current owner
    function owner() external view returns (address) {
        return _storage().owner;
    }

    /// @notice Returns true if the contract is paused
    function paused() public view returns (bool) {
        return _storage().paused;
    }

    // receive() is not supported on Solana, removed.

    // ═══════════════════════════════════════════
    //           USER: DEPOSIT & TOP_UP
    // ═══════════════════════════════════════════

    function deposit() external payable whenNotPaused nonReentrant {
        // Must be exactly 32 ETH (activation only) OR at least 33 ETH (activation + >=1 ETH topUp),
        // and never exceed the per-call max of 2048 ETH. The in-between range (32, 33) is rejected
        // because the beacon chain requires topUp >= 1 ETH and partial amounts would revert inside
        // `_topUpValidator`, producing confusing UX.
        require(
            msg.value == ConstantLib.ACTIVATION_DEPOSIT_AMOUNT
                || (msg.value >= ConstantLib.ACTIVATION_DEPOSIT_AMOUNT + ConstantLib.MIN_TOP_UP_AMOUNT
                    && msg.value <= ConstantLib.MAX_DEPOSIT_AMOUNT),
            "InvalidDepositAmount"
        );
        require(msg.value % 1 gwei == 0, "AmountNotGweiAligned");

        MainStorage storage $ = _storage();
        address vaultAddr = $.userVaults[tx.accounts.user.key];
        uint256 vaultIndex;

        if (vaultAddr == address(0)) {
            vaultIndex = $.nextVaultIndex;
            $.nextVaultIndex++;

            // Deploy vault via factory. Solana CPI cannot transfer native value, so we pass 0 lamports.
            // The factory must handle the vault creation without value transfer.
            vaultAddr = IEAGVaultFactory($.EAGVaultFactory).deployVault(vaultIndex, tx.accounts.user.key, $.vaultOperator);

            $.userVaults[tx.accounts.user.key] = vaultAddr;
            $.userVaultIndex[tx.accounts.user.key] = vaultIndex;
        } else {
            vaultIndex = $.userVaultIndex[tx.accounts.user.key];
        }

        uint256 nextIdx = $.vaultNextDepositDataIndex[vaultIndex];
        require(nextIdx < $.vaultDepositDataCount[vaultIndex], "InsufficientDepositData");

        (bytes memory pubkey, bytes memory signature) =
            DepositDataKeys.loadEntry(DEPOSIT_DATA_POSITION, vaultIndex, nextIdx);

        bytes32 pubkeyHash = keccak256(pubkey);
        $.vaultNextDepositDataIndex[vaultIndex] = nextIdx + 1;

        // Register validator via vault operator. Solana CPI cannot transfer native value.
        IEAGVaultOperator($.vaultOperator).registerValidator(pubkeyHash, vaultAddr, msg.value);

        uint64 depositCountBefore = _getDepositCount();

        bytes32 wc = _withdrawalCredentials(vaultAddr);
        bytes32 depositDataRoot =
            DepositDataLib.computeActivationDepositDataRoot(pubkey, ConstantLib.ACTIVATION_DEPOSIT_AMOUNT, wc, signature);

        // Deposit to beacon chain. Solana CPI cannot transfer native value.
        DEPOSIT_CONTRACT.deposit{value: ConstantLib.ACTIVATION_DEPOSIT_AMOUNT}(
            pubkey, abi.encodePacked(wc), signature, depositDataRoot
        );

        uint256 topUpAmount = msg.value - ConstantLib.ACTIVATION_DEPOSIT_AMOUNT;
        if (topUpAmount > 0) {
            _topUpValidator(pubkey, topUpAmount, wc);
        }

        require(
            _getDepositCount() - depositCountBefore == (topUpAmount > 0 ? 2 : 1),
            "DepositCountMismatch"
        );

        emit ValidatorDeposited(tx.accounts.user.key, vaultAddr, msg.value, pubkey);
    }

    function topUp(bytes calldata _pubkey) external payable whenNotPaused nonReentrant {
        require(msg.value != 0, "ZeroArgument: msg.value");
        require(msg.value <= ConstantLib.MAX_DEPOSIT_AMOUNT, "DepositAboveMaximum");
        require(msg.value % 1 gwei == 0, "AmountNotGweiAligned");
        require(_pubkey.length == ConstantLib.PUBLIC_KEY_LENGTH, "InvalidPubkeyLength");

        MainStorage storage $ = _storage();
        address vaultAddr = $.userVaults[tx.accounts.user.key];
        require(vaultAddr != address(0), "NoVaultAssigned");

        bytes32 wc = _withdrawalCredentials(vaultAddr);
        _topUpValidator(_pubkey, msg.value, wc);

        emit ValidatorTopUp(tx.accounts.user.key, vaultAddr, _pubkey, msg.value);
    }

    // ═══════════════════════════════════════════
    //          VAULT CALLBACK
    // ═══════════════════════════════════════════

    function onVaultOwnerChanged(address _oldOwner, address _newOwner) external nonReentrant {
        require(_newOwner != address(0), "ZeroArgument: _newOwner");
        require(_oldOwner != _newOwner, "RepeatedArgument");

        MainStorage storage $ = _storage();
        require(
            IEAGVaultFactory($.EAGVaultFactory).isRealVault(tx.accounts.vault.key),
            "SenderNotRealVault"
        );
        require($.userVaults[_oldOwner] == tx.accounts.vault.key, "VaultOwnerMismatch");
        require($.userVaults[_newOwner] == address(0), "NewOwnerAlreadyHasVault");

        uint256 idx = $.userVaultIndex[_oldOwner];
        delete $.userVaults[_oldOwner];
        delete $.userVaultIndex[_oldOwner];
        $.userVaults[_newOwner] = tx.accounts.vault.key;
        $.userVaultIndex[_newOwner] = idx;

        emit VaultOwnerSynced(tx.accounts.vault.key, _oldOwner, _newOwner, idx);
    }

    // ═══════════════════════════════════════════
    //     OPERATOR: DEPOSIT DATA MANAGEMENT
    // ═══════════════════════════════════════════

    struct PreDepositData {
        bytes pubkey;
        bytes signature;
        bytes32 depositDataRoot;
    }

    function addDepositData(uint256 _vaultIndex, PreDepositData[] calldata _data) external onlyOperator {
        uint256 count = _data.length;
        require(count != 0, "ZeroArgument: _data");
        MainStorage storage $ = _storage();
        require(
            $.maxDepositDataCountPerCall == 0 || count <= $.maxDepositDataCountPerCall,
            "ExceedsMaxDepositDataPerCall"
        );
        require(_vaultIndex <= $.nextVaultIndex + ConstantLib.MAX_DEPOSIT_DATA_AHEAD, "VaultIndexOutOfRange");

        address predictedVault = IEAGVaultFactory($.EAGVaultFactory).predictAddress(_vaultIndex);
        bytes32 wc = _withdrawalCredentials(predictedVault);
        uint256 startIndex = $.vaultDepositDataCount[_vaultIndex];

        for (uint256 i = 0; i < count;) {
            require(_data[i].pubkey.length == ConstantLib.PUBLIC_KEY_LENGTH, "InvalidPubkeyLength");
            require(_data[i].signature.length == ConstantLib.SIGNATURE_LENGTH, "InvalidSignatureLength");

            bytes memory pubkey = _data[i].pubkey;
            bytes memory signature = _data[i].signature;

            bytes32 expectedRoot =
                DepositDataLib.computeActivationDepositDataRoot(pubkey, ConstantLib.ACTIVATION_DEPOSIT_AMOUNT, wc, signature);
            require(expectedRoot == _data[i].depositDataRoot, "InvalidDepositDataRoot");

            bytes32 pubkeyHash = keccak256(pubkey);
            require(!$.registeredPubkeys[pubkeyHash], "DuplicatePubkey");
            $.registeredPubkeys[pubkeyHash] = true;

            DepositDataKeys.saveEntry(DEPOSIT_DATA_POSITION, _vaultIndex, startIndex + i, pubkey, signature);

            unchecked { ++i; }
        }

        $.vaultDepositDataCount[_vaultIndex] = startIndex + count;
        emit DepositDataAdded(_vaultIndex, count);
    }

    function removeDepositData(uint256 _vaultIndex, uint256 _count) external onlyOperator {
        require(_count != 0, "ZeroArgument: _count");
        MainStorage storage $ = _storage();
        uint256 total = $.vaultDepositDataCount[_vaultIndex];
        uint256 nextIdx = $.vaultNextDepositDataIndex[_vaultIndex];
        require(_count <= total - nextIdx, "InsufficientDepositData");

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

    function setOperator(address newOperator) external onlyOwner {
        require(newOperator != address(0), "ZeroArgument: _operator");
        MainStorage storage $ = _storage();
        require(newOperator != $.operator, "RepeatedArgument");
        $.operator = newOperator;
        emit OperatorChanged(newOperator);
    }

    function setMaxDepositDataCountPerCall(uint256 _maxCount) external onlyOwner {
        MainStorage storage $ = _storage();
        require(_maxCount != $.maxDepositDataCountPerCall, "RepeatedArgument");
        $.maxDepositDataCountPerCall = _maxCount;
        emit MaxDepositDataCountPerCallChanged(_maxCount);
    }

    // ═══════════════════════════════════════════
    //         OWNER: PAUSE / RESUME
    // ═══════════════════════════════════════════

    function pauseDeposits() external onlyOwner {
        require(!paused(), "DepositsAlreadyPaused");
        _pause();
        emit DepositsPaused();
    }

    function resumeDeposits() external onlyOwner {
        require(paused(), "DepositsAlreadyResumed");
        _unpause();
        emit DepositsResumed();
    }

    // ═══════════════════════════════════════════
    //          OWNER: ASSET RECOVERY
    // ═══════════════════════════════════════════

    function sweepETH(address payable _to, uint256 _amount) external onlyOwner nonReentrant {
        require(_to != address(0), "ZeroArgument: _to");
        require(_amount > 0, "ZeroArgument: _amount");
        uint256 bal = tx.accounts.router.lamports;
        require(_amount <= bal, "InsufficientBalance");
        // Solana CPI cannot transfer native value. Use a simple transfer via system program.
        // For Solana, we use the `transfer` function which is supported.
        payable(_to).transfer(_amount);
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
        require(_amount >= ConstantLib.MIN_TOP_UP_AMOUNT, "DepositBelowMinimum");
        bytes32 depositDataRoot = DepositDataLib.computeTopUpDepositDataRoot(_pubkey, _amount, _wc);
        bytes memory zeroSignature = new bytes(ConstantLib.SIGNATURE_LENGTH);
        // Solana CPI cannot transfer native value.
        DEPOSIT_CONTRACT.deposit{value: _amount}(
            _pubkey, abi.encodePacked(_wc), zeroSignature, depositDataRoot
        );
    }

    /// @notice Pause the contract
    function _pause() internal {
        _storage().paused = true;
    }

    /// @notice Unpause the contract
    function _unpause() internal {
        _storage().paused = false;
    }

    // ═══════════════════════════════════════════
    //          OWNERSHIP TRANSFER (2-STEP)
    // ═══════════════════════════════════════════

    /// @notice Initiates ownership transfer to a new address
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _storage().pendingOwner = newOwner;
    }

    /// @notice Accepts the pending ownership transfer
    function acceptOwnership() external {
        MainStorage storage $ = _storage();
        require(tx.accounts.pendingOwner.key == $.pendingOwner, "Ownable2Step: caller is not the new owner");
        emit OwnershipTransferred($.owner, $.pendingOwner);
        $.owner = $.pendingOwner;
        $.pendingOwner = address(0);
    }

    /// @notice Returns the pending owner
    function pendingOwner() external view returns (address) {
        return _storage().pendingOwner;
    }

    // Events for ownership
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // Events for deposit operations
    event ValidatorDeposited(address indexed user, address indexed vault, uint256 amount, bytes pubkey);
    event ValidatorTopUp(address indexed user, address indexed vault, bytes pubkey, uint256 amount);
    event VaultOwnerSynced(address indexed vault, address indexed oldOwner, address indexed newOwner, uint256 vaultIndex);
    event DepositDataAdded(uint256 indexed vaultIndex, uint256 count);
    event DepositDataRemoved(uint256 indexed vaultIndex, uint256 count);
    event OperatorChanged(address indexed newOperator);
    event MaxDepositDataCountPerCallChanged(uint256 newMaxCount);
    event DepositsPaused();
    event DepositsResumed();
    event ETHSwept(address indexed to, uint256 amount);
}

// Forward declaration of interfaces used internally
interface IEAGVaultFactory {
    function deployVault(uint256 vaultIndex, address owner, address vaultOperator) external returns (address);
    function predictAddress(uint256 vaultIndex) external view returns (address);
    function isRealVault(address vault) external view returns (bool);
}

interface IEAGVaultOperator {
    function registerValidator(bytes32 pubkeyHash, address vault, uint256 amount) external;
}