// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

contract BronToken {
    // ------------------------------
    // Storage
    // ------------------------------

    string public name;
    string public symbol;
    uint8 public constant decimals = 18;

    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10**18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    mapping(address => uint256) public lockedTokens;
    mapping(address => uint256) public loyaltyLockedTokens;

    address public multisig;
    address public bronDao;
    address public oftContract;
    address public loyaltyProgramContract;

    mapping(address => uint256[]) private votesCheckpoints;
    mapping(address => uint48[]) private votesTimestamps;
    uint256[] private totalCheckpoints;
    uint48[] private totalTimestamps;

    mapping(address => bool) public votesSynced;

    bool private _paused;

    // ------------------------------
    // Errors
    // ------------------------------

    error TransferLocked();
    error NotAuthorized();
    error InvalidValue();

    // ------------------------------
    // Events
    // ------------------------------

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event TokensLocked(address indexed account, uint256 value);
    event TokensUnlocked(address indexed account, uint256 value);
    event LockedTransferred(address indexed from, address indexed to, uint256 value);
    event CrosschainMint(address indexed account, uint256 value, address indexed sender);
    event CrosschainBurn(address indexed account, uint256 value, address indexed sender);
    event Paused(address account);
    event Unpaused(address account);

    // ------------------------------
    // Modifiers
    // ------------------------------

    modifier onlyOFT() {
        require(tx.origin == oftContract, "NotAuthorized");
        _;
    }

    modifier onlyMultisig() {
        require(tx.origin == multisig, "NotAuthorized");
        _;
    }

    modifier onlyLoyalty() {
        require(tx.origin == loyaltyProgramContract, "NotAuthorized");
        _;
    }

    modifier onlyBronDao() {
        require(tx.origin == bronDao, "NotAuthorized");
        _;
    }

    modifier whenNotPaused() {
        require(!_paused, "Pausable: paused");
        _;
    }

    // ------------------------------
    // Initializer
    // ------------------------------

    function initialize(address _bronTreasury, address _multisig, address _bronDao) external {
        require(bytes(name).length == 0, "Already initialized");
        name = "Bron";
        symbol = "BRON";

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
    // ERC20 functions
    // ------------------------------

    function totalSupply() public pure returns (uint256) {
        return TOTAL_SUPPLY;
    }

    function transfer(address to, uint256 value) external whenNotPaused returns (bool) {
        _transfer(tx.origin, to, value);
        return true;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[tx.origin][spender] = value;
        emit Approval(tx.origin, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external whenNotPaused returns (bool) {
        require(allowance[from][tx.origin] >= value, "ERC20: insufficient allowance");
        allowance[from][tx.origin] -= value;
        _transfer(from, to, value);
        return true;
    }

    // ------------------------------
    // Lock & unlock functions
    // ------------------------------

    function lock(address account, uint256 value) external onlyMultisig {
        require(value != 0 && value <= availableBalanceOf(account), "InvalidValue");

        _syncUserVotes(account);

        lockedTokens[account] += value;
        _lockVotes(account, value);

        emit TokensLocked(account, value);
    }

    function unlock(address account, uint256 value) external onlyMultisig {
        require(value != 0 && value <= lockedTokens[account], "InvalidValue");

        _syncUserVotes(account);

        lockedTokens[account] -= value;
        _unlockVotes(account, value);

        emit TokensUnlocked(account, value);
    }

    function transferLocked(address from, address to, uint256 value) external onlyBronDao {
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

    function transferSAFT(address to, uint256 value) external {
        address bronTreasury = address(0x0);
        require(tx.origin == bronTreasury, "NotAuthorized");
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

    function unlockSAFT(address account, uint256 value) external {
        address bronTreasury = address(0x0);
        require(tx.origin == bronTreasury, "NotAuthorized");
        require(value != 0 && value <= lockedTokens[account], "InvalidValue");

        _syncUserVotes(account);

        lockedTokens[account] -= value;
        _unlockVotes(account, value);

        emit TokensUnlocked(account, value);
    }

    function syncTotalVotesBatch(address[] calldata accounts) external {
        address bronTreasury = address(0x0);
        require(tx.origin == bronTreasury, "NotAuthorized");
        uint256 length = accounts.length;
        for (uint256 i = 0; i < length; i++) {
            _syncUserVotes(accounts[i]);
        }
    }

    // ------------------------------
    // Loyalty program functions
    // ------------------------------

    function loyaltyLock(address account, uint256 value) external onlyLoyalty {
        require(value != 0 && value <= availableBalanceOf(account), "InvalidValue");
        loyaltyLockedTokens[account] += value;
    }

    function loyaltyUnlock(address account, uint256 value) external onlyLoyalty {
        require(value != 0 && value <= loyaltyLockedTokens[account], "InvalidValue");
        loyaltyLockedTokens[account] -= value;
    }

    // ------------------------------
    // Crosschain functions
    // ------------------------------

    function crosschainMint(address account, uint256 value) external onlyOFT {
        require(value != 0 && TOTAL_SUPPLY >= totalSupply() + value, "InvalidValue");

        _mint(account, value);
        emit CrosschainMint(account, value, tx.origin);
    }

    function crosschainBurn(address account, uint256 value) external onlyOFT {
        require(value != 0 && value <= availableBalanceOf(account), "InvalidValue");

        _burn(account, value);
        emit CrosschainBurn(account, value, tx.origin);
    }

    // ------------------------------
    // View functions
    // ------------------------------

    function availableBalanceOf(address account) public view returns (uint256) {
        return balanceOf[account] - lockedTokens[account] - loyaltyLockedTokens[account];
    }

    function loyaltyLockedBalanceOf(address account) public view returns (uint256) {
        return loyaltyLockedTokens[account];
    }

    function getVotes(address account) public view returns (uint256) {
        uint256[] storage checkpoints = votesCheckpoints[account];
        if (checkpoints.length == 0) return 0;
        return checkpoints[checkpoints.length - 1];
    }

    function getPastVotes(address account, uint256 timepoint) public view returns (uint256) {
        require(block.timestamp >= timepoint, "InvalidValue");
        uint48[] storage timestamps = votesTimestamps[account];
        uint256[] storage checkpoints = votesCheckpoints[account];
        if (timestamps.length == 0) return 0;
        for (int256 i = int256(timestamps.length) - 1; i >= 0; i--) {
            if (timestamps[uint256(i)] <= timepoint) {
                return checkpoints[uint256(i)];
            }
        }
        return 0;
    }

    function getPastTotalAvailableVotingSupply(uint256 timepoint) public view returns (uint256) {
        require(block.timestamp >= timepoint, "InvalidValue");
        if (totalTimestamps.length == 0) return 0;
        for (int256 i = int256(totalTimestamps.length) - 1; i >= 0; i--) {
            if (totalTimestamps[uint256(i)] <= timepoint) {
                return totalCheckpoints[uint256(i)];
            }
        }
        return 0;
    }

    function getPastTotalSupply(uint256 timepoint) public view returns (uint256) {
        return getPastTotalAvailableVotingSupply(timepoint);
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
        _pause();
    }

    function unpause() external onlyMultisig {
        _unpause();
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
    // Internal functions
    // ------------------------------

    function _transfer(address from, address to, uint256 value) internal whenNotPaused {
        require(from == address(0) || value <= availableBalanceOf(from), "TransferLocked");

        if (from != address(0)) _syncUserVotes(from);
        if (to != address(0)) _syncUserVotes(to);

        _update(from, to, value);
    }

    function _update(address from, address to, uint256 value) internal {
        if (from != address(0)) {
            balanceOf[from] -= value;
        }
        if (to != address(0)) {
            balanceOf[to] += value;
        }
        emit Transfer(from, to, value);
        _transferVotingUnits(from, to, value);
    }

    function _mint(address account, uint256 value) internal {
        balanceOf[account] += value;
        emit Transfer(address(0), account, value);
        _transferVotingUnits(address(0), account, value);
    }

    function _burn(address account, uint256 value) internal {
        balanceOf[account] -= value;
        emit Transfer(account, address(0), value);
        _transferVotingUnits(account, address(0), value);
    }

    function _unlockVotes(address account, uint256 value) internal {
        _pushTotal(_add, SafeCast.toUint208(value));
        _pushAccount(account, _add, SafeCast.toUint208(value));
    }

    function _lockVotes(address account, uint256 value) internal {
        _pushTotal(_subtract, SafeCast.toUint208(value));
        _pushAccount(account, _subtract, SafeCast.toUint208(value));
    }

    function _transferVotingUnits(address from, address to, uint256 amount) internal {
        if (from == address(0)) {
            _pushTotal(_add, SafeCast.toUint208(amount));
        }
        if (to == address(0)) {
            _pushTotal(_subtract, SafeCast.toUint208(amount));
        }
        _moveVotes(from, to, amount);
    }

    function _moveVotes(address from, address to, uint256 amount) internal {
        if (from != to && amount > 0) {
            if (from != address(0)) {
                _pushAccount(from, _subtract, SafeCast.toUint208(amount));
            }
            if (to != address(0)) {
                _pushAccount(to, _add, SafeCast.toUint208(amount));
            }
        }
    }

    function _pushTotal(function(uint208, uint208) pure returns (uint208) op, uint208 delta) private {
        uint208 latest = totalCheckpoints.length > 0 ? uint208(totalCheckpoints[totalCheckpoints.length - 1]) : 0;
        uint208 newValue = op(latest, delta);
        totalCheckpoints.push(newValue);
        totalTimestamps.push(SafeCast.toUint48(block.timestamp));
    }

    function _pushAccount(address account, function(uint208, uint208) pure returns (uint208) op, uint208 delta) private {
        uint256[] storage checkpoints = votesCheckpoints[account];
        uint48[] storage timestamps = votesTimestamps[account];
        uint208 latest = checkpoints.length > 0 ? uint208(checkpoints[checkpoints.length - 1]) : 0;
        uint208 newValue = op(latest, delta);
        checkpoints.push(newValue);
        timestamps.push(SafeCast.toUint48(block.timestamp));
    }

    function _add(uint208 a, uint208 b) private pure returns (uint208) {
        return a + b;
    }

    function _subtract(uint208 a, uint208 b) private pure returns (uint208) {
        return a - b;
    }

    function _syncUserVotes(address account) internal {
        if (votesSynced[account]) return;
        votesSynced[account] = true;

        uint256 amount = balanceOf[account] - lockedTokens[account];
        if (amount > 0) {
            _unlockVotes(account, amount);
        }
    }

    function _pause() internal {
        _paused = true;
        emit Paused(tx.origin);
    }

    function _unpause() internal {
        _paused = false;
        emit Unpaused(tx.origin);
    }
}

library SafeCast {
    function toUint48(uint256 value) internal pure returns (uint48) {
        require(value <= type(uint48).max, "SafeCast: value doesn't fit in 48 bits");
        return uint48(value);
    }

    function toUint208(uint256 value) internal pure returns (uint208) {
        require(value <= type(uint208).max, "SafeCast: value doesn't fit in 208 bits");
        return uint208(value);
    }
}