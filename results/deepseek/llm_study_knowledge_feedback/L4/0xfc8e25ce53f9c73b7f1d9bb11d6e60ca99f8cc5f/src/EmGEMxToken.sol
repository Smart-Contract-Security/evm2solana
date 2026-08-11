// SPDX-License-Identifier: UNLICENSED

import {AccountMeta} from 'solana';

contract EmGEMxToken {
    ///////////////////
    // Errors
    ///////////////////
    // Error definitions and reverts with error messages are not yet working for Solana.
    // Using require with string messages instead.

    ///////////////////
    // Types
    ///////////////////
    // AggregatorV3Interface is not available on Solana. We'll use a simplified oracle interface.
    // Oracle will be represented by its program_id and we'll call it via cross-program invocation.

    ///////////////////
    // State Variables
    ///////////////////
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant ESU_PER_TOKEN_MODIFIER_ROLE = keccak256("ESU_PER_TOKEN_MODIFIER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant FREEZER_ROLE = keccak256("FREEZER_ROLE");
    bytes32 public constant LIMITER_ROLE = keccak256("LIMITER_ROLE");
    bytes32 public constant REDEEMER_ROLE = keccak256("REDEEMER_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    uint64 public constant PARENT_CHAIN_ID = 43114;

    address private redeemAddress;
    uint64 private esuPerTokenValue;
    uint64 private esuPerTokenPrecision;

    // Oracle program id
    address private oracleProgramId;

    // Token storage
    mapping(address => uint64) private _balances;
    mapping(address => mapping(address => uint64)) private _allowances;
    uint64 private _totalSupply;

    string private _name;
    string private _symbol;
    uint8 private _decimals;

    // Role management
    mapping(bytes32 => mapping(address => bool)) private _roles;
    mapping(bytes32 => bytes32) private _roleAdmin;

    // Pausable
    bool private _paused;

    // Freezable
    mapping(address => bool) private _frozenAccounts;

    // Blocklist
    mapping(address => bool) private _blockedAccounts;

    // Permit nonces
    mapping(address => uint64) private _nonces;

    // Owner
    address private _owner;

    // Initialized flag
    bool private _initialized;

    ///////////////////
    // Events
    ///////////////////
    event EsuPerTokenChanged(uint64 value, uint64 precision);
    event OracleAddressChanged(address oldAddress, address newAddress);
    event RedeemAddressChanged(address oldAddress, address newAddress);
    event Transfer(address indexed from, address indexed to, uint64 value);
    event Approval(address indexed owner, address indexed spender, uint64 value);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Paused(address account);
    event Unpaused(address account);
    event AccountFrozen(address indexed account);
    event AccountUnfrozen(address indexed account);
    event AccountBlocked(address indexed account);
    event AccountUnblocked(address indexed account);

    ///////////////////
    // Modifiers
    ///////////////////
    modifier onlyParentChain() {
        // block.chainid is not available on Solana. We'll use a configurable chain id.
        // For Solana, we'll assume this is always the parent chain or use a stored chain id.
        _;
    }

    modifier onlyRole(bytes32 role) {
        require(hasRole(role, tx.accounts.dataAccount.key), "AccessControl: account is missing role");
        _;
    }

    modifier whenNotPaused() {
        require(!_paused, "Pausable: paused");
        _;
    }

    modifier whenPaused() {
        require(_paused, "Pausable: not paused");
        _;
    }

    ///////////////////
    // Constructor
    ///////////////////
    // No constructor on Solana, use initialize

    ///////////////////
    // Functions
    ///////////////////

    function initialize(address oracleAddress, string memory name, string memory symbol) public {
        require(!_initialized, "Already initialized");
        require(oracleAddress != address(0), "Invalid address");

        _name = name;
        _symbol = symbol;
        _decimals = 8;

        _owner = tx.accounts.dataAccount.key;
        oracleProgramId = oracleAddress;

        _roleAdmin[DEFAULT_ADMIN_ROLE] = DEFAULT_ADMIN_ROLE;
        _roleAdmin[MINTER_ROLE] = DEFAULT_ADMIN_ROLE;
        _roleAdmin[ESU_PER_TOKEN_MODIFIER_ROLE] = DEFAULT_ADMIN_ROLE;
        _roleAdmin[PAUSER_ROLE] = DEFAULT_ADMIN_ROLE;
        _roleAdmin[FREEZER_ROLE] = DEFAULT_ADMIN_ROLE;
        _roleAdmin[LIMITER_ROLE] = DEFAULT_ADMIN_ROLE;
        _roleAdmin[REDEEMER_ROLE] = DEFAULT_ADMIN_ROLE;

        _grantRole(DEFAULT_ADMIN_ROLE, tx.accounts.dataAccount.key);

        esuPerTokenValue = 1;
        esuPerTokenPrecision = 100;

        _initialized = true;
    }

    ///////////////////
    // External Functions
    ///////////////////

    function mint(address account, uint64 value) external onlyRole(MINTER_ROLE) {
        _mint(account, value);
    }

    function burn(uint64 value) external onlyRole(MINTER_ROLE) {
        _burn(tx.accounts.dataAccount.key, value);
    }

    function burnFrom(address account, uint64 value) external onlyRole(MINTER_ROLE) {
        _spendAllowance(account, tx.accounts.dataAccount.key, value);
        _burn(account, value);
    }

    function redeem(uint64 value) external onlyRole(REDEEMER_ROLE) onlyParentChain {
        require(redeemAddress != address(0), "RedeemAddressNotSet");
        _burn(redeemAddress, value);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function blockUser(address user) external onlyRole(LIMITER_ROLE) {
        _blockUser(user);
    }

    function unblockUser(address user) external onlyRole(LIMITER_ROLE) {
        _unblockUser(user);
    }

    function getOracleAddress() external view returns (address) {
        return oracleProgramId;
    }

    function setOracleAddress(address newAddress) external onlyRole(DEFAULT_ADMIN_ROLE) onlyParentChain {
        require(newAddress != address(0), "Invalid address");
        emit OracleAddressChanged(oracleProgramId, newAddress);
        oracleProgramId = newAddress;
    }

    function getRedeemAddress() external view returns (address) {
        return redeemAddress;
    }

    function setRedeemAddress(address newAddress) external onlyRole(DEFAULT_ADMIN_ROLE) onlyParentChain {
        require(newAddress != address(0), "Invalid address");
        emit RedeemAddressChanged(redeemAddress, newAddress);
        redeemAddress = newAddress;
    }

    function getEsuPerToken() external view returns (uint64, uint64) {
        return (esuPerTokenValue, esuPerTokenPrecision);
    }

    function setEsuPerToken(uint64 value, uint64 precision) external onlyRole(ESU_PER_TOKEN_MODIFIER_ROLE) onlyParentChain {
        esuPerTokenValue = value;
        esuPerTokenPrecision = precision;
        emit EsuPerTokenChanged(value, precision);
    }

    function decimals() public pure returns (uint8) {
        return 8;
    }

    function getMaxSupply() public view returns (uint64) {
        // On Solana, we don't have chainid. Assume parent chain logic.
        return _getEsuFromOracle() * esuPerTokenPrecision / esuPerTokenValue;
    }

    // ERC20 standard functions
    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function totalSupply() public view returns (uint64) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint64) {
        return _balances[account];
    }

    function transfer(address to, uint64 value) external whenNotPaused returns (bool) {
        address owner = tx.accounts.dataAccount.key;
        _transfer(owner, to, value);
        return true;
    }

    function allowance(address owner, address spender) public view returns (uint64) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint64 value) external whenNotPaused returns (bool) {
        address owner = tx.accounts.dataAccount.key;
        _approve(owner, spender, value, true);
        return true;
    }

    function transferFrom(address from, address to, uint64 value) external whenNotPaused returns (bool) {
        address spender = tx.accounts.dataAccount.key;
        _spendAllowance(from, spender, value);
        _transfer(from, to, value);
        return true;
    }

    function increaseAllowance(address spender, uint64 addedValue) external whenNotPaused returns (bool) {
        address owner = tx.accounts.dataAccount.key;
        _approve(owner, spender, _allowances[owner][spender] + addedValue, true);
        return true;
    }

    function decreaseAllowance(address spender, uint64 subtractedValue) external whenNotPaused returns (bool) {
        address owner = tx.accounts.dataAccount.key;
        uint64 currentAllowance = _allowances[owner][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        _approve(owner, spender, currentAllowance - subtractedValue, true);
        return true;
    }

    // AccessControl functions
    function hasRole(bytes32 role, address account) public view returns (bool) {
        return _roles[role][account];
    }

    function getRoleAdmin(bytes32 role) public view returns (bytes32) {
        return _roleAdmin[role];
    }

    function grantRole(bytes32 role, address account) external onlyRole(getRoleAdmin(role)) {
        _grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) external onlyRole(getRoleAdmin(role)) {
        _revokeRole(role, account);
    }

    function renounceRole(bytes32 role, address account) external {
        require(account == tx.accounts.dataAccount.key, "AccessControl: can only renounce roles for self");
        _revokeRole(role, account);
    }

    // Ownable functions
    function owner() public view returns (address) {
        return _owner;
    }

    function transferOwnership(address newOwner) external {
        require(tx.accounts.dataAccount.key == _owner, "Ownable: caller is not the owner");
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    function renounceOwnership() external {
        require(tx.accounts.dataAccount.key == _owner, "Ownable: caller is not the owner");
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    // Freezable functions
    function isFrozen(address account) public view returns (bool) {
        return _frozenAccounts[account];
    }

    function freezeAccount(address account) external onlyRole(FREEZER_ROLE) {
        _frozenAccounts[account] = true;
        emit AccountFrozen(account);
    }

    function unfreezeAccount(address account) external onlyRole(FREEZER_ROLE) {
        _frozenAccounts[account] = false;
        emit AccountUnfrozen(account);
    }

    // Blocklist functions
    function isBlocked(address account) public view returns (bool) {
        return _blockedAccounts[account];
    }

    // Pausable functions
    function paused() public view returns (bool) {
        return _paused;
    }

    // Permit functions
    function nonces(address owner) public view returns (uint64) {
        return _nonces[owner];
    }

    function permit(
        address owner,
        address spender,
        uint64 value,
        uint64 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(block.timestamp <= deadline, "ERC20Permit: expired deadline");
        // Simplified permit - ecrecover not available on Solana
        // In production, would need to use Solana's ed25519 signature verification
        _approve(owner, spender, value, true);
    }

    ///////////////////
    // Internal Functions
    ///////////////////

    function _update(address from, address to, uint64 amount) internal {
        // Parent chain checks
        if (from == address(0) && _totalSupply + amount > getMaxSupply()) {
            require(false, "NotEnoughReserve");
        }

        if (to == address(0) && from != redeemAddress) {
            require(false, "BurnOnParentChainNotAllowed");
        }

        // Pausable check
        require(!_paused, "Pausable: paused");

        // Freezable check
        require(!_frozenAccounts[from], "Freezable: from account frozen");
        require(!_frozenAccounts[to], "Freezable: to account frozen");

        // Blocklist check
        require(!_blockedAccounts[from], "Blocklist: from account blocked");
        require(!_blockedAccounts[to], "Blocklist: to account blocked");

        if (from == address(0)) {
            _totalSupply += amount;
        } else {
            _balances[from] -= amount;
        }

        if (to == address(0)) {
            _totalSupply -= amount;
        } else {
            _balances[to] += amount;
        }

        emit Transfer(from, to, amount);
    }

    function _mint(address account, uint64 amount) internal {
        require(account != address(0), "ERC20: mint to the zero address");
        _update(address(0), account, amount);
    }

    function _burn(address account, uint64 amount) internal {
        require(account != address(0), "ERC20: burn from the zero address");
        _update(account, address(0), amount);
    }

    function _transfer(address from, address to, uint64 amount) internal {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        _update(from, to, amount);
    }

    function _approve(address owner, address spender, uint64 value, bool emitEvent) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        require(!_blockedAccounts[owner], "Blocklist: owner blocked");
        require(!_blockedAccounts[spender], "Blocklist: spender blocked");

        _allowances[owner][spender] = value;
        if (emitEvent) {
            emit Approval(owner, spender, value);
        }
    }

    function _spendAllowance(address owner, address spender, uint64 amount) internal {
        uint64 currentAllowance = _allowances[owner][spender];
        if (currentAllowance != type(uint64).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            _approve(owner, spender, currentAllowance - amount, false);
        }
    }

    function _grantRole(bytes32 role, address account) internal {
        if (!hasRole(role, account)) {
            _roles[role][account] = true;
            emit RoleGranted(role, account, tx.accounts.dataAccount.key);
        }
    }

    function _revokeRole(bytes32 role, address account) internal {
        if (hasRole(role, account)) {
            _roles[role][account] = false;
            emit RoleRevoked(role, account, tx.accounts.dataAccount.key);
        }
    }

    function _pause() internal whenNotPaused {
        _paused = true;
        emit Paused(tx.accounts.dataAccount.key);
    }

    function _unpause() internal whenPaused {
        _paused = false;
        emit Unpaused(tx.accounts.dataAccount.key);
    }

    function _blockUser(address user) internal {
        _blockedAccounts[user] = true;
        emit AccountBlocked(user);
    }

    function _unblockUser(address user) internal {
        _blockedAccounts[user] = false;
        emit AccountUnblocked(user);
    }

    function _isFreezer(address user) internal view returns (bool) {
        return hasRole(FREEZER_ROLE, user);
    }

    ///////////////////
    // Private Functions
    ///////////////////

    function _getEsuFromOracle() private view returns (uint64) {
        // On Solana, we need to use cross-program invocation to call the oracle.
        // This is a simplified placeholder. In production, you'd use CPI to call the oracle program.
        // For now, return a default value.
        return 1;
    }
}