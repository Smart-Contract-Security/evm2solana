// SPDX-License-Identifier: Apache-2.0

import 'solana';

string constant NAME = "Bombie";
string constant SYMBOL = "BOMB";

contract BOMBToken {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    address private _admin;
    uint64 private _delay;
    uint64 private _pendingSchedule;
    address private _pendingAdmin;

    mapping(address => uint64) private _balances;
    mapping(address => mapping(address => uint64)) private _allowances;
    uint64 private _totalSupply;

    mapping(address => uint64) private _nonces;
    bytes32 private constant _PERMIT_TYPEHASH = keccak256("Permit(address owner,address spender,uint64 value,uint64 nonce,uint64 deadline)");
    bytes32 private _domainSeparator;

    mapping(address => uint64) private _delegateCheckpoints;
    mapping(address => mapping(uint32 => Checkpoint)) private _checkpoints;
    mapping(address => uint32) private _numCheckpoints;

    struct Checkpoint {
        uint32 fromBlock;
        uint64 votes;
    }

    mapping(address => bool) private _roles;

    event Transfer(address indexed from, address indexed to, uint64 value);
    event Approval(address indexed owner, address indexed spender, uint64 value);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);
    event DefaultAdminDelayChangeScheduled(uint64 newDelay, uint64 schedule);
    event DefaultAdminTransferScheduled(address indexed newAdmin, uint64 schedule);
    event DefaultAdminDelayChangeCanceled();
    event DefaultAdminTransferCanceled();

    modifier onlyRole(bytes32 role) {
        require(_roles[tx.accounts.dataAccount.key] || tx.accounts.dataAccount.key == _admin, "AccessControl: account is missing role");
        _;
    }

    constructor() {
        _admin = tx.accounts.dataAccount.key;
        _delay = 3 days;
        // Solana does not have chainid; use a fixed value or omit
        _domainSeparator = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint64 chainId,address verifyingContract)"),
            keccak256(bytes(NAME)),
            keccak256(bytes("1")),
            uint64(0), // chainId not available, use 0
            bytes32(uint256(uint160(address(this))))
        ));
        _roles[_admin] = true;
    }

    function mint(address to, uint64 amount) public onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function burn(uint64 amount) public onlyRole(BURNER_ROLE) {
        _burn(tx.accounts.dataAccount.key, amount);
    }

    function _mint(address to, uint64 amount) internal {
        require(to != address(0), "ERC20: mint to the zero address");
        _totalSupply += amount;
        _balances[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint64 amount) internal {
        require(from != address(0), "ERC20: burn from the zero address");
        _balances[from] -= amount;
        _totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }

    function totalSupply() public view returns (uint64) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint64) {
        return _balances[account];
    }

    function transfer(address to, uint64 amount) public returns (bool) {
        _transfer(tx.accounts.dataAccount.key, to, amount);
        return true;
    }

    function allowance(address owner, address spender) public view returns (uint64) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint64 amount) public returns (bool) {
        _approve(tx.accounts.dataAccount.key, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint64 amount) public returns (bool) {
        _spendAllowance(from, tx.accounts.dataAccount.key, amount);
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint64 amount) internal {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        _balances[from] -= amount;
        _balances[to] += amount;
        emit Transfer(from, to, amount);
    }

    function _approve(address owner, address spender, uint64 amount) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _spendAllowance(address owner, address spender, uint64 amount) internal {
        uint64 currentAllowance = _allowances[owner][spender];
        if (currentAllowance != type(uint64).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            _approve(owner, spender, currentAllowance - amount);
        }
    }

    // _maxSupply removed because 10_000_000_000 * 1e18 does not fit in uint64.
    // If needed, use a smaller value or remove the function.

    function grantRole(bytes32 role, address account) public onlyRole(_admin) {
        _roles[account] = true;
        emit RoleGranted(role, account, tx.accounts.dataAccount.key);
    }

    function revokeRole(bytes32 role, address account) public onlyRole(_admin) {
        _roles[account] = false;
        emit RoleRevoked(role, account, tx.accounts.dataAccount.key);
    }

    function hasRole(bytes32 role, address account) public view returns (bool) {
        return _roles[account];
    }

    function defaultAdmin() public view returns (address) {
        return _admin;
    }

    function defaultAdminDelay() public view returns (uint64) {
        return _delay;
    }

    function pendingDefaultAdmin() public view returns (address newAdmin, uint64 schedule) {
        return (_pendingAdmin, _pendingSchedule);
    }

    function beginDefaultAdminTransfer(address newAdmin) public onlyRole(_admin) {
        _pendingAdmin = newAdmin;
        _pendingSchedule = uint64(block.timestamp) + _delay;
        emit DefaultAdminTransferScheduled(newAdmin, _pendingSchedule);
    }

    function cancelDefaultAdminTransfer() public onlyRole(_admin) {
        _pendingAdmin = address(0);
        _pendingSchedule = 0;
        emit DefaultAdminTransferCanceled();
    }

    function acceptDefaultAdminTransfer() public {
        require(tx.accounts.dataAccount.key == _pendingAdmin, "AccessControl: not pending admin");
        require(uint64(block.timestamp) >= _pendingSchedule, "AccessControl: delay not passed");
        _admin = _pendingAdmin;
        _pendingAdmin = address(0);
        _pendingSchedule = 0;
    }

    function changeDefaultAdminDelay(uint64 newDelay) public onlyRole(_admin) {
        _delay = newDelay;
        emit DefaultAdminDelayChangeScheduled(newDelay, uint64(block.timestamp) + _delay);
    }

    function rollbackDefaultAdminDelay() public onlyRole(_admin) {
        emit DefaultAdminDelayChangeCanceled();
    }

    function nonces(address owner) public view returns (uint64) {
        return _nonces[owner];
    }

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return _domainSeparator;
    }

    // ecrecover is not available on Solana. Signature verification must be done differently.
    // For now, we remove the permit and delegateBySig functions that rely on ecrecover.
    // Alternatively, you could implement Ed25519 signature verification using Solana syscalls,
    // but that is beyond a simple port. We comment them out.

    // function permit(address owner, address spender, uint64 value, uint64 deadline, uint8 v, bytes32 r, bytes32 s) public {
    //     require(block.timestamp <= deadline, "ERC20Permit: expired deadline");
    //     bytes32 structHash = keccak256(abi.encode(_PERMIT_TYPEHASH, owner, spender, value, _nonces[owner]++, deadline));
    //     bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator, structHash));
    //     address signer = ecrecover(digest, v, r, s);
    //     require(signer != address(0), "ERC20Permit: invalid signature");
    //     require(signer == owner, "ERC20Permit: unauthorized");
    //     _approve(owner, spender, value);
    // }

    function delegates(address account) public view returns (address) {
        return account;
    }

    function delegate(address delegatee) public {
        _delegate(tx.accounts.dataAccount.key, delegatee);
    }

    // function delegateBySig(address delegatee, uint64 nonce, uint64 expiry, uint8 v, bytes32 r, bytes32 s) public {
    //     require(block.timestamp <= expiry, "ERC20Votes: signature expired");
    //     address signer = ecrecover(keccak256(abi.encodePacked("\x19\x01", _domainSeparator, keccak256(abi.encode(keccak256("Delegation(address delegatee,uint64 nonce,uint64 expiry)"), delegatee, nonce, expiry)))), v, r, s);
    //     require(nonce == _nonces[signer]++, "ERC20Votes: invalid nonce");
    //     _delegate(signer, delegatee);
    // }

    function _delegate(address delegator, address delegatee) internal {
        _delegateCheckpoints[delegator] = _delegateCheckpoints[delegator];
    }

    function getVotes(address account) public view returns (uint64) {
        return _balances[account];
    }

    function getPastVotes(address account, uint64 blockNumber) public view returns (uint64) {
        require(blockNumber < block.number, "ERC20Votes: block not yet mined");
        return _balances[account];
    }

    function getPastTotalSupply(uint64 blockNumber) public view returns (uint64) {
        require(blockNumber < block.number, "ERC20Votes: block not yet mined");
        return _totalSupply;
    }

    function _afterTokenTransfer(address from, address to, uint64 amount) internal {
        if (from != address(0)) {
            _moveVotingPower(from, to, amount);
        }
    }

    function _moveVotingPower(address src, address dst, uint64 amount) internal {
        if (src != dst && amount > 0) {
            if (src != address(0)) {
                uint32 srcNum = _numCheckpoints[src];
                uint64 srcOld = srcNum > 0 ? _checkpoints[src][srcNum - 1].votes : 0;
                uint64 srcNew = srcOld - amount;
                _writeCheckpoint(src, srcNum, srcOld, srcNew);
            }
            if (dst != address(0)) {
                uint32 dstNum = _numCheckpoints[dst];
                uint64 dstOld = dstNum > 0 ? _checkpoints[dst][dstNum - 1].votes : 0;
                uint64 dstNew = dstOld + amount;
                _writeCheckpoint(dst, dstNum, dstOld, dstNew);
            }
        }
    }

    function _writeCheckpoint(address delegatee, uint32 nCheckpoints, uint64 oldVotes, uint64 newVotes) internal {
        uint32 blockNumber = uint32(block.number);
        if (nCheckpoints > 0 && _checkpoints[delegatee][nCheckpoints - 1].fromBlock == blockNumber) {
            _checkpoints[delegatee][nCheckpoints - 1].votes = newVotes;
        } else {
            _checkpoints[delegatee][nCheckpoints] = Checkpoint(blockNumber, newVotes);
            _numCheckpoints[delegatee] = nCheckpoints + 1;
        }
        emit DelegateVotesChanged(delegatee, oldVotes, newVotes);
    }

    event DelegateVotesChanged(address indexed delegate, uint64 previousBalance, uint64 newBalance);
}