// SPDX-License-Identifier: MIT

import 'solana';

contract BronToken {
    // ------------------------------
    // Constants
    // ------------------------------

    uint64 constant TOTAL_SUPPLY = 1000000000 * 10**18; // Adjust as needed

    // ------------------------------
    // Storage
    // ------------------------------

    address public multisig;
    address public bronDao;
    address public oftContract;
    address public loyaltyProgramContract;

    mapping(address => uint64) public lockedTokens;
    mapping(address => uint64) public loyaltyLockedTokens;
    mapping(address => bool) public votesSynced;

    // Simplified checkpoint storage using arrays
    mapping(address => uint64[]) private votesCheckpoints;
    mapping(address => uint48[]) private votesTimestamps;
    uint64[] private totalCheckpoints;
    uint48[] private totalTimestamps;

    string public name;
    string public symbol;
    uint8 public decimals;
    uint64 public totalSupply;
    mapping(address => uint64) public balanceOf;
    mapping(address => mapping(address => uint64)) public allowance;

    bool private paused;

    // ------------------------------
    // Events
    // ------------------------------

    event Transfer(address indexed from, address indexed to, uint64 value);
    event Approval(address indexed owner, address indexed spender, uint64 value);
    event TokensLocked(address indexed account, uint64 value);
    event TokensUnlocked(address indexed account, uint64 value);
    event LockedTransferred(address indexed from, address indexed to, uint64 value);
    event CrosschainMint(address indexed account, uint64 value, address indexed sender);
    event CrosschainBurn(address indexed account, uint64 value, address indexed sender);
    event Paused(address account);
    event Unpaused(address account);

    // ------------------------------
    // Initializer
    // ------------------------------

    function initialize(address _bronTreasury, address _multisig, address _bronDao) external {
        require(multisig == address(0), "Already initialized");

        name = "Bron";
        symbol = "BRON";
        decimals = 18;

        if (_bronTreasury != address(0)) {
            votesSynced[_bronTreasury] = true;
            _mint(_bronTreasury, TOTAL_SUPPLY);
            lockedTokens[_bronTreasury] = TOTAL_SUPPLY;
            _lockVotes(_bronTreasury, TOTAL_SUPPLY);
        }

        multisig = _multisig;
        bronDao = _bronDao;
    }

    // ------------------------------
    // Modifiers
    // ------------------------------

    modifier onlyOFT() {
        require(tx.accounts.dataAccount.key == oftContract, "NotAuthorized");
        _;
    }

    modifier onlyMultisig() {
        require(tx.accounts.dataAccount.key == multisig, "NotAuthorized");
        _;
    }

    modifier onlyLoyalty() {
        require(tx.accounts.dataAccount.key == loyaltyProgramContract, "NotAuthorized");
        _;
    }

    modifier onlyBronDao() {
        require(tx.accounts.dataAccount.key == bronDao, "NotAuthorized");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Paused");
        _;
    }

    // ------------------------------
    // Lock & unlock functions
    // ------------------------------

    function lock(address account, uint64 value) external onlyMultisig {
        require(value != 0 && value <= availableBalanceOf(account), "InvalidValue");

        _syncUserVotes(account);

        lockedTokens[account] += value;
        _lockVotes(account, value);

        emit TokensLocked(account, value);
    }

    function unlock(address account, uint64 value) external onlyMultisig {
        require(value != 0 && value <= lockedTokens[account], "InvalidValue");

        _syncUserVotes(account);

        lockedTokens[account] -= value;
        _unlockVotes(account, value);

        emit TokensUnlocked(account, value);
    }

    function transferLocked(address from, address to, uint64 value) external onlyBronDao {
        require(value != 0 && value <= lockedTokens[from], "InvalidValue");

        _syncUserVotes(from);
        _syncUserVotes(to);

        lockedTokens[from] -= value;
        lockedTokens[to] += value;

        _unlockVotes(from, value);
        _transfer(from, to, value);
        _lockVotes(to, value);

        emit LockedTransferred(from, to, value);
    }

    function transferSAFT(address to, uint64 value) external {
        address bronTreasury = address(0x86b77F2ed584e6Ed3478C1F14e6D7b47D0AB0cc7);
        require(tx.accounts.dataAccount.key == bronTreasury, "NotAuthorized");
        require(value != 0 && value <= lockedTokens[bronTreasury], "InvalidValue");

        _syncUserVotes(bronTreasury);
        _syncUserVotes(to);

        lockedTokens[bronTreasury] -= value;
        lockedTokens[to] += value;

        _unlockVotes(bronTreasury, value);
        _transfer(bronTreasury, to, value);
        _lockVotes(to, value);

        emit LockedTransferred(bronTreasury, to, value);
    }

    function unlockSAFT(address account, uint64 value) external {
        address bronTreasury = address(0x86b77F2ed584e6Ed3478C1F14e6D7b47D0AB0cc7);
        require(tx.accounts.dataAccount.key == bronTreasury, "NotAuthorized");
        require(value != 0 && value <= lockedTokens[account], "InvalidValue");

        _syncUserVotes(account);

        lockedTokens[account] -= value;
        _unlockVotes(account, value);

        emit TokensUnlocked(account, value);
    }

    function syncTotalVotesBatch(address[] calldata accounts) external {
        address bronTreasury = address(0x86b77F2ed584e6Ed3478C1F14e6D7b47D0AB0cc7);
        require(tx.accounts.dataAccount.key == bronTreasury, "NotAuthorized");
        uint64 length = uint64(accounts.length);
        for (uint64 i = 0; i < length; i++) {
            _syncUserVotes(accounts[i]);
        }
    }

    // ------------------------------
    // Loyalty program functions
    // ------------------------------

    function loyaltyLock(address account, uint64 value) external onlyLoyalty {
        require(value != 0 && value <= availableBalanceOf(account), "InvalidValue");
        loyaltyLockedTokens[account] += value;
    }

    function loyaltyUnlock(address account, uint64 value) external onlyLoyalty {
        require(value != 0 && value <= loyaltyLockedTokens[account], "InvalidValue");
        loyaltyLockedTokens[account] -= value;
    }

    // ------------------------------
    // Crosschain functions
    // ------------------------------

    function crosschainMint(address account, uint64 value) external onlyOFT {
        require(value != 0 && TOTAL_SUPPLY >= totalSupply + value, "InvalidValue");

        _mint(account, value);
        emit CrosschainMint(account, value, tx.accounts.dataAccount.key);
    }

    function crosschainBurn(address account, uint64 value) external onlyOFT {
        require(value != 0 && value <= availableBalanceOf(account), "InvalidValue");

        _burn(account, value);
        emit CrosschainBurn(account, value, tx.accounts.dataAccount.key);
    }

    // ------------------------------
    // View functions
    // ------------------------------

    function availableBalanceOf(address account) public view returns (uint64) {
        return balanceOf[account] - lockedTokens[account] - loyaltyLockedTokens[account];
    }

    function loyaltyLockedBalanceOf(address account) public view returns (uint64) {
        return loyaltyLockedTokens[account];
    }

    function getVotes(address account) public view returns (uint64) {
        uint64[] storage checkpoints = votesCheckpoints[account];
        if (checkpoints.length == 0) {
            return 0;
        }
        return checkpoints[checkpoints.length - 1];
    }

    function getPastVotes(address account, uint64 timepoint) public view returns (uint64) {
        require(block.timestamp >= timepoint, "InvalidValue");
        return _upperLookupRecent(votesCheckpoints[account], votesTimestamps[account], timepoint);
    }

    function getPastTotalAvailableVotingSupply(uint64 timepoint) public view returns (uint64) {
        require(block.timestamp >= timepoint, "InvalidValue");
        return _upperLookupRecent(totalCheckpoints, totalTimestamps, timepoint);
    }

    function getPastTotalSupply(uint64 timepoint) public view returns (uint64) {
        require(block.timestamp >= timepoint, "InvalidValue");
        return _upperLookupRecent(totalCheckpoints, totalTimestamps, timepoint);
    }

    function clock() public view returns (uint48) {
        return uint48(block.timestamp);
    }

    function CLOCK_MODE() public pure returns (string memory) {
        return "mode=timestamp";
    }

    // ------------------------------
    // Admin functions
    // ------------------------------

    function pause() external onlyMultisig {
        paused = true;
        emit Paused(tx.accounts.dataAccount.key);
    }

    function unpause() external onlyMultisig {
        paused = false;
        emit Unpaused(tx.accounts.dataAccount.key);
    }

    function updateMultisig(address _multisig) external onlyMultisig {
        multisig = _multisig;
    }

    function updateBronDao(address _bronDao) external onlyBronDao {
        bronDao = _bronDao;
    }

    function updateOFTContract(address _oftContract) external onlyBronDao {
        oftContract = _oftContract;
    }

    // ------------------------------
    // ERC20 functions
    // ------------------------------

    function transfer(address to, uint64 value) external whenNotPaused returns (bool) {
        _transfer(tx.accounts.dataAccount.key, to, value);
        return true;
    }

    function approve(address spender, uint64 value) external whenNotPaused returns (bool) {
        allowance[tx.accounts.dataAccount.key][spender] = value;
        emit Approval(tx.accounts.dataAccount.key, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint64 value) external whenNotPaused returns (bool) {
        require(allowance[from][tx.accounts.dataAccount.key] >= value, "Insufficient allowance");
        allowance[from][tx.accounts.dataAccount.key] -= value;
        _transfer(from, to, value);
        return true;
    }

    // ------------------------------
    // Internal functions
    // ------------------------------

    function _transfer(address from, address to, uint64 value) internal {
        require(from != address(0), "Transfer from zero address");
        require(to != address(0), "Transfer to zero address");
        require(value <= availableBalanceOf(from), "TransferLocked");

        if (from != address(0)) _syncUserVotes(from);
        if (to != address(0)) _syncUserVotes(to);

        balanceOf[from] -= value;
        balanceOf[to] += value;

        _transferVotingUnits(from, to, value);

        emit Transfer(from, to, value);
    }

    function _mint(address account, uint64 value) internal {
        require(account != address(0), "Mint to zero address");

        totalSupply += value;
        balanceOf[account] += value;

        _transferVotingUnits(address(0), account, value);

        emit Transfer(address(0), account, value);
    }

    function _burn(address account, uint64 value) internal {
        require(account != address(0), "Burn from zero address");
        require(value <= availableBalanceOf(account), "TransferLocked");

        totalSupply -= value;
        balanceOf[account] -= value;

        _transferVotingUnits(account, address(0), value);

        emit Transfer(account, address(0), value);
    }

    function _unlockVotes(address account, uint64 value) internal {
        _pushTotal(_add, value);
        _pushAccount(account, _add, value);
    }

    function _lockVotes(address account, uint64 value) internal {
        _pushTotal(_subtract, value);
        _pushAccount(account, _subtract, value);
    }

    function _transferVotingUnits(address from, address to, uint64 amount) internal {
        if (from == address(0)) {
            _pushTotal(_add, amount);
        }
        if (to == address(0)) {
            _pushTotal(_subtract, amount);
        }
        _moveVotes(from, to, amount);
    }

    function _moveVotes(address from, address to, uint64 amount) internal {
        if (from != to && amount > 0) {
            if (from != address(0)) {
                _pushAccount(from, _subtract, amount);
            }
            if (to != address(0)) {
                _pushAccount(to, _add, amount);
            }
        }
    }

    function _pushTotal(function(uint64, uint64) pure returns (uint64) op, uint64 delta) private {
        uint64 latest = totalCheckpoints.length > 0 ? totalCheckpoints[totalCheckpoints.length - 1] : 0;
        uint64 newValue = op(latest, delta);
        totalCheckpoints.push(newValue);
        totalTimestamps.push(uint48(block.timestamp));
    }

    function _pushAccount(address account, function(uint64, uint64) pure returns (uint64) op, uint64 delta) private {
        uint64[] storage checkpoints = votesCheckpoints[account];
        uint48[] storage timestamps = votesTimestamps[account];
        uint64 latest = checkpoints.length > 0 ? checkpoints[checkpoints.length - 1] : 0;
        uint64 newValue = op(latest, delta);
        checkpoints.push(newValue);
        timestamps.push(uint48(block.timestamp));
    }

    function _add(uint64 a, uint64 b) private pure returns (uint64) {
        return a + b;
    }

    function _subtract(uint64 a, uint64 b) private pure returns (uint64) {
        return a - b;
    }

    function _syncUserVotes(address account) internal {
        if (votesSynced[account]) return;
        votesSynced[account] = true;

        uint64 amount = balanceOf[account] - lockedTokens[account];
        if (amount > 0) {
            _unlockVotes(account, amount);
        }
    }

    function _upperLookupRecent(uint64[] storage values, uint48[] storage timestamps, uint64 timepoint) private view returns (uint64) {
        uint64 length = uint64(timestamps.length);
        if (length == 0) {
            return 0;
        }
        for (uint64 i = length; i > 0; i--) {
            if (timestamps[i - 1] <= timepoint) {
                return values[i - 1];
            }
        }
        return 0;
    }
}