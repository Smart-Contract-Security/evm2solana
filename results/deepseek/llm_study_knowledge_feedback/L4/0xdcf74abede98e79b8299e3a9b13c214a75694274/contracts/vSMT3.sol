import 'solana';

contract SmtVestingV3 {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = keccak256("DEFAULT_ADMIN_ROLE");

    address public acceptedToken;
    uint64 public vestingStartTime;
    string public KYA;

    mapping(address => bool) public whitelisted;
    mapping(address => uint64) public claimedAmount;
    mapping(address => uint64) public balances;
    mapping(address => mapping(address => uint64)) public allowances;
    mapping(bytes32 => mapping(address => bool)) public roles;

    uint64 public totalSupply;
    bool public paused;

    event Claim(address indexed owner, uint64 amount);
    event AcceptedTokenSet(address _acceptedToken);
    event StartTimeSet(uint64 vestingStartTime);
    event WhitelistedAddress(address whitelisted);
    event Transfer(address indexed from, address indexed to, uint64 value);
    event Approval(address indexed owner, address indexed spender, uint64 value);
    event Paused(address account);
    event Unpaused(address account);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    modifier zeroAddressCheck(address _address) {
        if (_address == address(0)) {
            revert("ZeroAddressError");
        }
        _;
    }

    modifier isDistributionTimeSet() {
        if (vestingStartTime == 0) {
            revert("StartTimeNotSetError");
        }
        _;
    }

    modifier onlyRole(bytes32 role) {
        require(hasRole(role, tx.accounts.dataAccount.key), "AccessControl: account is missing role");
        _;
    }

    function hasRole(bytes32 role, address account) internal view returns (bool) {
        return roles[role][account];
    }

    function _grantRole(bytes32 role, address account) internal {
        if (!hasRole(role, account)) {
            roles[role][account] = true;
            emit RoleGranted(role, account, tx.accounts.dataAccount.key);
        }
    }

    function _revokeRole(bytes32 role, address account) internal {
        if (hasRole(role, account)) {
            roles[role][account] = false;
            emit RoleRevoked(role, account, tx.accounts.dataAccount.key);
        }
    }

    function grantRole(bytes32 role, address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(role, account);
    }

    function renounceRole(bytes32 role, address account) external {
        require(account == tx.accounts.dataAccount.key, "AccessControl: can only renounce roles for self");
        _revokeRole(role, account);
    }

    function name() public pure returns (string memory) {
        return "Swarm Markets Vesting Token v3";
    }

    function symbol() public pure returns (string memory) {
        return "vSMT3";
    }

    function decimals() public pure returns (uint8) {
        return 18;
    }

    function balanceOf(address account) public view returns (uint64) {
        return balances[account];
    }

    function allowance(address owner, address spender) public view returns (uint64) {
        return allowances[owner][spender];
    }

    function approve(address spender, uint64 amount) public returns (bool) {
        address owner = tx.accounts.dataAccount.key;
        _approve(owner, spender, amount);
        return true;
    }

    function _approve(address owner, address spender, uint64 amount) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function transfer(address to, uint64 amount) public returns (bool) {
        address owner = tx.accounts.dataAccount.key;
        _transfer(owner, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint64 amount) public returns (bool) {
        address spender = tx.accounts.dataAccount.key;
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function _spendAllowance(address owner, address spender, uint64 amount) internal {
        uint64 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint64).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }

    function _transfer(address from, address to, uint64 amount) internal {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        _update(from, to, amount);
    }

    function _mint(address account, uint64 amount) internal {
        require(account != address(0), "ERC20: mint to the zero address");
        totalSupply += amount;
        balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint64 amount) internal {
        require(account != address(0), "ERC20: burn from the zero address");
        uint64 accountBalance = balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            balances[account] = accountBalance - amount;
        }
        totalSupply -= amount;
        emit Transfer(account, address(0), amount);
    }

    function _update(address from, address to, uint64 value) internal {
        require(!paused, "ERC20Pausable: token transfer while paused");
        bool checkTransfer = whitelisted[from] || from == address(0) || to == address(0);
        require(checkTransfer, "OnlyWhitelistedTransfersError");

        if (from == address(0)) {
            // mint
        } else {
            uint64 fromBalance = balances[from];
            require(fromBalance >= value, "ERC20: transfer amount exceeds balance");
            unchecked {
                balances[from] = fromBalance - value;
            }
        }

        if (to == address(0)) {
            // burn
        } else {
            balances[to] += value;
        }

        emit Transfer(from, to, value);
    }

    function _pause() internal {
        require(!paused, "Pausable: paused");
        paused = true;
        emit Paused(tx.accounts.dataAccount.key);
    }

    function _unpause() internal {
        require(paused, "Pausable: not paused");
        paused = false;
        emit Unpaused(tx.accounts.dataAccount.key);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    @payer(payer)
    @space(512 + 32)
    constructor(address _admin, address _SMT) {
        require(_admin != address(0), "ZeroAddressError");
        require(_SMT != address(0), "ZeroAddressError");
        acceptedToken = _SMT;
        emit AcceptedTokenSet(_SMT);

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);
    }

    function setKYA(string calldata _KYA) external onlyRole(DEFAULT_ADMIN_ROLE) {
        KYA = _KYA;
    }

    function setStartTime(uint64 _startTime) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (vestingStartTime > 0) {
            revert("StartTimeSetError");
        }
        if (_startTime < block.timestamp) {
            revert("StartTimeError");
        }

        vestingStartTime = _startTime;
        emit StartTimeSet(_startTime);
    }

    function addWhitelistedAddress(address _address) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_address != address(0), "ZeroAddressError");
        whitelisted[_address] = true;
        emit WhitelistedAddress(_address);
    }

    function deposit(uint64 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address caller = tx.accounts.dataAccount.key;
        // External call to acceptedToken.transferFrom
        (bool success, bytes memory ret) = acceptedToken.call{accounts: []}(abi.encodeWithSignature("transferFrom(address,address,uint64)", caller, address(this), _amount));
        require(success, "transferFrom failed");
        _mint(caller, _amount);
    }

    function claim(uint64 amount) public isDistributionTimeSet {
        address caller = tx.accounts.dataAccount.key;
        uint64 claimableAmount = amountToClaim(caller);
        if (amount == 0) {
            revert("NothingToClaimError");
        }
        if (claimableAmount < amount) {
            revert("AmountToClaimTooBigError");
        }

        claimedAmount[caller] += amount;
        _burn(caller, amount);

        // External call to acceptedToken.transfer
        (bool success, bytes memory ret) = acceptedToken.call{accounts: []}(abi.encodeWithSignature("transfer(address,uint64)", caller, amount));
        require(success, "transfer failed");

        emit Claim(caller, amount);
    }

    function claimMaximumTokensPerMonth() external {
        claim(amountToClaim(tx.accounts.dataAccount.key));
    }

    function amountToClaim(address account) public view returns (uint64 amount) {
        if (vestingStartTime == 0) {
            revert("StartTimeNotSetError");
        }

        uint64 initialBalance = balanceOf(account) + claimedAmount[account];
        uint64 currentTime = uint64(block.timestamp);

        if (currentTime >= vestingStartTime + (5 * 30 days)) {
            return initialBalance - claimedAmount[account];
        } else if (currentTime >= vestingStartTime + (4 * 30 days)) {
            return (initialBalance * 5) / 6 - claimedAmount[account];
        } else if (currentTime >= vestingStartTime + (3 * 30 days)) {
            return (initialBalance * 4) / 6 - claimedAmount[account];
        } else if (currentTime >= vestingStartTime + (2 * 30 days)) {
            return (initialBalance * 3) / 6 - claimedAmount[account];
        } else if (currentTime >= vestingStartTime + (30 days)) {
            return (initialBalance * 2) / 6 - claimedAmount[account];
        } else if (currentTime >= vestingStartTime) {
            return (initialBalance / 6) - claimedAmount[account];
        } else {
            return 0;
        }
    }

    function getCurrentLockedAmount() external view returns (uint64 balanceOfAcceptedToken) {
        // External call to acceptedToken.balanceOf
        (bool success, bytes memory ret) = acceptedToken.call{accounts: []}(abi.encodeWithSignature("balanceOf(address)", address(this)));
        require(success, "balanceOf failed");
        balanceOfAcceptedToken = abi.decode(ret, (uint64));
    }
}