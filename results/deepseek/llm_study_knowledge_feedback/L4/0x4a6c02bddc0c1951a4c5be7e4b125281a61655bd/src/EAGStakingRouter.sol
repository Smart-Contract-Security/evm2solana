// SPDX-License-Identifier: GPL-3.0

import {DepositDataLib} from "./base/DepositDataLib.sol";

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

    /// @dev Activation deposit amount in lamports (32 ETH in gwei * 1e9)
    uint64 private constant ACTIVATION_DEPOSIT_AMOUNT = 32_000_000_000 * 1_000_000_000;
    /// @dev Minimum top-up amount in lamports (1 ETH in gwei * 1e9)
    uint64 private constant MIN_TOP_UP_AMOUNT = 1_000_000_000 * 1_000_000_000;
    /// @dev Maximum deposit amount in lamports
    uint64 private constant MAX_DEPOSIT_AMOUNT = 1_000_000_000_000 * 1_000_000_000;
    /// @dev Public key length for BLS keys
    uint256 private constant PUBLIC_KEY_LENGTH = 48;
    /// @dev Signature length for BLS signatures
    uint256 private constant SIGNATURE_LENGTH = 96;
    /// @dev Maximum deposit data entries ahead of current vault index
    uint256 private constant MAX_DEPOSIT_DATA_AHEAD = 100;
    /// @dev 0x02 prefix for withdrawal credentials
    uint256 private constant WC_0X02_PREFIX = 0x0200000000000000000000000000000000000000000000000000000000000000;

    // ═══════════════════════════════════════════
    //               IMMUTABLES
    // ═══════════════════════════════════════════

    /// @notice The Beacon Chain deposit contract
    /// @dev Immutable is safe in upgradeable contracts because it lives in the
    ///      implementation's bytecode, not storage. However, any future
    ///      implementation MUST be deployed with the same `_depositContract`
    ///      argument (the deployment script asserts equality before upgrade).
    address public immutable DEPOSIT_CONTRACT;

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
        bool _paused;
        address _owner;
        address _pendingOwner;
        bool _initialized;
        bool _reentrancyLock;
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
        require(tx.accounts.dataAccount.key == _storage().operator, "SenderNotOperator");
        _;
    }

    modifier onlyOwner() {
        require(tx.accounts.dataAccount.key == _storage()._owner, "NotOwner");
        _;
    }

    modifier whenNotPaused() {
        require(!_storage()._paused, "Paused");
        _;
    }

    modifier nonReentrant() {
        MainStorage storage $ = _storage();
        require(!$._reentrancyLock, "Reentrant");
        $._reentrancyLock = true;
        _;
        $._reentrancyLock = false;
    }

    modifier initializer() {
        MainStorage storage $ = _storage();
        require(!$._initialized, "AlreadyInitialized");
        $._initialized = true;
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
        require(_depositContract != address(0), "ZeroArgument: _depositContract");
        DEPOSIT_CONTRACT = _depositContract;
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
        require(_initEAGVaultFactory != address(0), "ZeroArgument: _EAGVaultFactory");
        require(_initOwner != address(0), "ZeroArgument: _initOwner");
        require(_initOperator != address(0), "ZeroArgument: _operator");
        require(_initVaultOperator != address(0), "ZeroArgument: _vaultOperator");

        MainStorage storage $ = _storage();
        $._owner = _initOwner;
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

    function paused() external view returns (bool) {
        return _storage()._paused;
    }

    function owner() external view returns (address) {
        return _storage()._owner;
    }

    // ═══════════════════════════════════════════
    //           USER: DEPOSIT & TOP_UP
    // ═══════════════════════════════════════════

    function deposit() external whenNotPaused nonReentrant {
        uint64 value = tx.accounts.dataAccount.lamports;
        require(
            value == ACTIVATION_DEPOSIT_AMOUNT
                || (value >= ACTIVATION_DEPOSIT_AMOUNT + MIN_TOP_UP_AMOUNT
                    && value <= MAX_DEPOSIT_AMOUNT),
            "InvalidDepositAmount"
        );
        require(value % 1_000_000_000 == 0, "AmountNotGweiAligned");

        MainStorage storage $ = _storage();
        address vaultAddr = $.userVaults[tx.accounts.dataAccount.key];
        uint256 vaultIndex;

        if (vaultAddr == address(0)) {
            vaultIndex = $.nextVaultIndex;
            $.nextVaultIndex++;

            vaultAddr = IEAGVaultFactory($.EAGVaultFactory).deployVault(vaultIndex, tx.accounts.dataAccount.key, $.vaultOperator);

            $.userVaults[tx.accounts.dataAccount.key] = vaultAddr;
            $.userVaultIndex[tx.accounts.dataAccount.key] = vaultIndex;
        } else {
            vaultIndex = $.userVaultIndex[tx.accounts.dataAccount.key];
        }

        uint256 nextIdx = $.vaultNextDepositDataIndex[vaultIndex];
        require(nextIdx < $.vaultDepositDataCount[vaultIndex], "InsufficientDepositData");

        (bytes memory pubkey, bytes memory signature) =
            _loadEntry(DEPOSIT_DATA_POSITION, vaultIndex, nextIdx);

        bytes32 pubkeyHash = keccak256(pubkey);
        $.vaultNextDepositDataIndex[vaultIndex] = nextIdx + 1;

        IEAGVaultOperator($.vaultOperator).registerValidator(pubkeyHash, vaultAddr, value);

        uint64 depositCountBefore = _getDepositCount();

        bytes32 wc = _withdrawalCredentials(vaultAddr);
        bytes32 depositDataRoot =
            DepositDataLib.computeActivationDepositDataRoot(pubkey, ACTIVATION_DEPOSIT_AMOUNT, wc, signature);

        IDepositContract(DEPOSIT_CONTRACT).deposit(
            pubkey, abi.encodePacked(wc), signature, depositDataRoot
        );

        uint256 topUpAmount = value - ACTIVATION_DEPOSIT_AMOUNT;
        if (topUpAmount > 0) {
            _topUpValidator(pubkey, topUpAmount, wc);
        }

        require(
            _getDepositCount() - depositCountBefore == (topUpAmount > 0 ? 2 : 1),
            "DepositCountMismatch"
        );

        emit ValidatorDeposited(tx.accounts.dataAccount.key, vaultAddr, value, pubkey);
    }

    function topUp(bytes calldata _pubkey) external whenNotPaused nonReentrant {
        uint64 value = tx.accounts.dataAccount.lamports;
        require(value != 0, "ZeroArgument: msg.value");
        require(value <= MAX_DEPOSIT_AMOUNT, "DepositAboveMaximum");
        require(value % 1_000_000_000 == 0, "AmountNotGweiAligned");
        require(_pubkey.length == PUBLIC_KEY_LENGTH, "InvalidPubkeyLength");

        MainStorage storage $ = _storage();
        address vaultAddr = $.userVaults[tx.accounts.dataAccount.key];
        require(vaultAddr != address(0), "NoVaultAssigned");

        bytes32 wc = _withdrawalCredentials(vaultAddr);
        _topUpValidator(_pubkey, value, wc);

        emit ValidatorTopUp(tx.accounts.dataAccount.key, vaultAddr, _pubkey, value);
    }

    // ═══════════════════════════════════════════
    //          VAULT CALLBACK
    // ═══════════════════════════════════════════

    function onVaultOwnerChanged(address _oldOwner, address _newOwner) external nonReentrant {
        require(_newOwner != address(0), "ZeroArgument: _newOwner");
        require(_oldOwner != _newOwner, "RepeatedArgument");

        MainStorage storage $ = _storage();
        require(
            IEAGVaultFactory($.EAGVaultFactory).isRealVault(tx.accounts.dataAccount.key),
            "SenderNotRealVault"
        );
        require($.userVaults[_oldOwner] == tx.accounts.dataAccount.key, "VaultOwnerMismatch");
        require($.userVaults[_newOwner] == address(0), "NewOwnerAlreadyHasVault");

        uint256 idx = $.userVaultIndex[_oldOwner];
        delete $.userVaults[_oldOwner];
        delete $.userVaultIndex[_oldOwner];
        $.userVaults[_newOwner] = tx.accounts.dataAccount.key;
        $.userVaultIndex[_newOwner] = idx;

        emit VaultOwnerSynced(tx.accounts.dataAccount.key, _oldOwner, _newOwner, idx);
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
        require(_vaultIndex <= $.nextVaultIndex + MAX_DEPOSIT_DATA_AHEAD, "VaultIndexOutOfRange");

        address predictedVault = IEAGVaultFactory($.EAGVaultFactory).predictAddress(_vaultIndex);
        bytes32 wc = _withdrawalCredentials(predictedVault);
        uint256 startIndex = $.vaultDepositDataCount[_vaultIndex];

        for (uint256 i = 0; i < count;) {
            require(_data[i].pubkey.length == PUBLIC_KEY_LENGTH, "InvalidPubkeyLength");
            require(_data[i].signature.length == SIGNATURE_LENGTH, "InvalidSignatureLength");

            bytes memory pubkey = _data[i].pubkey;
            bytes memory signature = _data[i].signature;

            bytes32 expectedRoot =
                DepositDataLib.computeActivationDepositDataRoot(pubkey, ACTIVATION_DEPOSIT_AMOUNT, wc, signature);
            require(expectedRoot == _data[i].depositDataRoot, "InvalidDepositDataRoot");

            bytes32 pubkeyHash = keccak256(pubkey);
            require(!$.registeredPubkeys[pubkeyHash], "DuplicatePubkey");
            $.registeredPubkeys[pubkeyHash] = true;

            _saveEntry(DEPOSIT_DATA_POSITION, _vaultIndex, startIndex + i, pubkey, signature);

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
            bytes memory pubkey = _loadPubkey(DEPOSIT_DATA_POSITION, _vaultIndex, lastIdx);
            delete $.registeredPubkeys[keccak256(pubkey)];
            _clearEntry(DEPOSIT_DATA_POSITION, _vaultIndex, lastIdx);
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
        require(!_storage()._paused, "DepositsAlreadyPaused");
        _storage()._paused = true;
        emit DepositsPaused();
    }

    function resumeDeposits() external onlyOwner {
        require(_storage()._paused, "DepositsAlreadyResumed");
        _storage()._paused = false;
        emit DepositsResumed();
    }

    // ═══════════════════════════════════════════
    //          OWNER: ASSET RECOVERY
    // ═══════════════════════════════════════════

    function sweepETH(address payable _to, uint256 _amount) external onlyOwner nonReentrant {
        require(_to != address(0), "ZeroArgument: _to");
        require(_amount > 0, "ZeroArgument: _amount");
        uint256 bal = tx.accounts.dataAccount.lamports;
        require(_amount <= bal, "InsufficientBalance");
        (bool success, ) = _to.call{value: _amount}("");
        require(success, "TransferFailed");
        emit ETHSwept(_to, _amount);
    }

    // ═══════════════════════════════════════════
    //          INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════

    /// @notice Read and parse the current deposit count from the Beacon deposit contract
    /// @return The deposit count as uint64
    function _getDepositCount() internal view returns (uint64) {
        bytes memory data = IDepositContract(DEPOSIT_CONTRACT).get_deposit_count();
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
        return bytes32(WC_0X02_PREFIX | bytes32(uint256(uint160(_vault))));
    }

    /// @notice Top up a validator via zero-signature deposit
    /// @dev TopUp minimum is 1 ETH per Beacon chain rules
    /// @param _pubkey Validator BLS public key (48 bytes)
    /// @param _amount Amount to deposit in wei (must be >= 1 ETH)
    /// @param _wc Withdrawal credentials for the validator
    function _topUpValidator(bytes memory _pubkey, uint256 _amount, bytes32 _wc) internal {
        require(_amount >= MIN_TOP_UP_AMOUNT, "DepositBelowMinimum");
        bytes32 depositDataRoot = DepositDataLib.computeTopUpDepositDataRoot(_pubkey, _amount, _wc);
        bytes memory zeroSignature = new bytes(SIGNATURE_LENGTH);
        IDepositContract(DEPOSIT_CONTRACT).deposit(
            _pubkey, abi.encodePacked(_wc), zeroSignature, depositDataRoot
        );
    }

    // ═══════════════════════════════════════════
    //     DEPOSIT DATA SLOT HELPERS
    // ═══════════════════════════════════════════

    /// @dev Compute the storage slot for a deposit data entry
    function _depositDataSlot(bytes32 _position, uint256 _vaultIndex, uint256 _entryIndex) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(_position, _vaultIndex, _entryIndex));
    }

    /// @dev Save a pubkey + signature pair into a deterministic slot
    function _saveEntry(bytes32 _position, uint256 _vaultIndex, uint256 _entryIndex, bytes memory _pubkey, bytes memory _signature) private {
        bytes32 slot = _depositDataSlot(_position, _vaultIndex, _entryIndex);
        assembly {
            sstore(slot, mload(add(_pubkey, 32)))
            sstore(add(slot, 1), mload(add(_pubkey, 64)))
            sstore(add(slot, 2), mload(add(_signature, 32)))
            sstore(add(slot, 3), mload(add(_signature, 64)))
            sstore(add(slot, 4), mload(add(_signature, 96)))
        }
    }

    /// @dev Load a pubkey + signature pair from a deterministic slot
    function _loadEntry(bytes32 _position, uint256 _vaultIndex, uint256 _entryIndex) private view returns (bytes memory pubkey, bytes memory signature) {
        bytes32 slot = _depositDataSlot(_position, _vaultIndex, _entryIndex);
        pubkey = new bytes(48);
        signature = new bytes(96);
        assembly {
            mstore(add(pubkey, 32), sload(slot))
            mstore(add(pubkey, 64), sload(add(slot, 1)))
            mstore(add(signature, 32), sload(add(slot, 2)))
            mstore(add(signature, 64), sload(add(slot, 3)))
            mstore(add(signature, 96), sload(add(slot, 4)))
        }
    }

    /// @dev Load only the pubkey from a deterministic slot
    function _loadPubkey(bytes32 _position, uint256 _vaultIndex, uint256 _entryIndex) private view returns (bytes memory pubkey) {
        bytes32 slot = _depositDataSlot(_position, _vaultIndex, _entryIndex);
        pubkey = new bytes(48);
        assembly {
            mstore(add(pubkey, 32), sload(slot))
            mstore(add(pubkey, 64), sload(add(slot, 1)))
        }
    }

    /// @dev Clear a deposit data entry from storage
    function _clearEntry(bytes32 _position, uint256 _vaultIndex, uint256 _entryIndex) private {
        bytes32 slot = _depositDataSlot(_position, _vaultIndex, _entryIndex);
        assembly {
            sstore(slot, 0)
            sstore(add(slot, 1), 0)
            sstore(add(slot, 2), 0)
            sstore(add(slot, 3), 0)
            sstore(add(slot, 4), 0)
        }
    }

    // ═══════════════════════════════════════════
    //                EVENTS
    // ═══════════════════════════════════════════

    event ValidatorDeposited(address indexed user, address vault, uint256 amount, bytes pubkey);
    event ValidatorTopUp(address indexed user, address vault, bytes pubkey, uint256 amount);
    event VaultOwnerSynced(address vault, address oldOwner, address newOwner, uint256 vaultIndex);
    event DepositDataAdded(uint256 vaultIndex, uint256 count);
    event DepositDataRemoved(uint256 vaultIndex, uint256 count);
    event OperatorChanged(address newOperator);
    event MaxDepositDataCountPerCallChanged(uint256 newMaxCount);
    event DepositsPaused();
    event DepositsResumed();
    event ETHSwept(address to, uint256 amount);
}

interface IEAGVaultFactory {
    function deployVault(uint256 vaultIndex, address owner, address vaultOperator) external returns (address);
    function isRealVault(address vault) external view returns (bool);
    function predictAddress(uint256 vaultIndex) external view returns (address);
}

interface IEAGVaultOperator {
    function registerValidator(bytes32 pubkeyHash, address vault, uint64 amount) external;
}

interface IDepositContract {
    function deposit(bytes calldata pubkey, bytes calldata withdrawalCredentials, bytes calldata signature, bytes32 depositDataRoot) external;
    function get_deposit_count() external view returns (bytes memory);
}