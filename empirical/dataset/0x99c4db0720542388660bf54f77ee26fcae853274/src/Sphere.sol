// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title Sphere (SPHERE)
/// @notice ERC20 with on-chain reflection accounting. A 5% swap tax (collected by the
///         Uniswap v4 hook in SPHERE) is redistributed to every holder proportionally to
///         their balance via a magnified per-share accumulator (no iteration, unlimited
///         holders). A separate 1% swap tax is collected by the hook in ETH for self-funding.
/// @dev    Balances auto-grow: `balanceOf` = crystallized base + unclaimed reflections.
///         Unclaimed reflections are realized into the base balance whenever an account
///         transacts. The physical reflection tokens live in this contract until claimed.
contract Sphere is IERC20, IERC20Metadata, Ownable {
    // ------------------------------- metadata ------------------------------- //
    string private constant _NAME = "Sphere";
    string private constant _SYMBOL = "SPHERE";
    uint8 private constant _DECIMALS = 18;
    uint256 private immutable _totalSupplyFixed;

    // ---------------------------- reflections ------------------------------- //
    uint256 private constant MAG = 2 ** 96; // fixed-point magnitude

    mapping(address => uint256) private _base; // crystallized balances
    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _magPerShare; // cumulative reflections * MAG / eligibleSupply
    mapping(address => int256) private _corr; // per-account magnitude correction
    mapping(address => uint256) private _withdrawn; // reflections already crystallized

    uint256 public eligibleSupply; // sum of base balances of reward-eligible accounts
    uint256 public reflectionReserve; // SPHERE held by this contract owed to holders
    uint256 public pendingUndistributed; // reflections waiting for eligibleSupply > 0
    uint256 public totalReflected; // lifetime SPHERE redistributed to holders

    mapping(address => bool) public excludedFromRewards;

    // ------------------------ limits & launch control ----------------------- //
    bool public tradingEnabled;
    uint256 public launchBlock;
    uint256 public deadBlocks = 2; // blocks of anti-snipe buy protection after launch
    bool public limitsEnabled = true;
    uint256 public maxTxAmount;
    uint256 public maxWalletAmount;

    mapping(address => bool) public isExcludedFromLimits; // maxTx + launch gate bypass
    mapping(address => bool) public isExcludedFromMaxWallet;

    address public hook; // the Uniswap v4 hook authorized to push reflections

    // -------------------------------- events -------------------------------- //
    event ReflectionDistributed(uint256 amount, uint256 totalReflected);
    event ReflectionClaimed(address indexed account, uint256 amount);
    event HookSet(address indexed hook);
    event TradingEnabled(uint256 blockNumber);
    event LimitsRemoved();
    event ExcludedFromRewards(address indexed account, bool excluded);
    event ExcludedFromLimits(address indexed account, bool excluded);
    event ExcludedFromMaxWallet(address indexed account, bool excluded);

    error TradingNotEnabled();
    error MaxTxExceeded();
    error MaxWalletExceeded();
    error OnlyHook();
    error Unbacked();
    error ZeroAddress();

    modifier onlyHook() {
        if (msg.sender != hook) revert OnlyHook();
        _;
    }

    constructor(uint256 supply, address owner_) Ownable(owner_) {
        _totalSupplyFixed = supply;
        maxTxAmount = supply * 2 / 100; // 2%
        maxWalletAmount = supply * 2 / 100; // 2%

        _setExcludedFromLimits(owner_, true);
        _setExcludedFromLimits(address(this), true);
        _setExcludedFromMaxWallet(owner_, true);
        _setExcludedFromMaxWallet(address(this), true);
        _setExcludedFromRewards(owner_, true);
        _setExcludedFromRewards(address(this), true);
        _setExcludedFromRewards(address(0), true);

        // Mint full supply to owner (owner is reward-excluded, so eligibleSupply stays 0
        // until real holders acquire tokens).
        _mint(owner_, supply);
    }

    // ------------------------------- views ---------------------------------- //
    function name() external pure returns (string memory) {
        return _NAME;
    }

    function symbol() external pure returns (string memory) {
        return _SYMBOL;
    }

    function decimals() external pure returns (uint8) {
        return _DECIMALS;
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupplyFixed;
    }

    function balanceOf(address account) public view returns (uint256) {
        if (account == address(this)) {
            return _base[account] - reflectionReserve;
        }
        if (excludedFromRewards[account]) return _base[account];
        return _base[account] + _pendingReflection(account);
    }

    function pendingReflectionOf(address account) external view returns (uint256) {
        if (excludedFromRewards[account]) return 0;
        return _pendingReflection(account);
    }

    function allowance(address owner_, address spender) external view returns (uint256) {
        return _allowances[owner_][spender];
    }

    // ------------------------------ mutators -------------------------------- //
    function approve(address spender, uint256 value) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _update(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        _spendAllowance(from, msg.sender, value);
        _update(from, to, value);
        return true;
    }

    /// @notice Crystallize your own pending reflections into your spendable balance.
    function claimReflections() external {
        _crystallize(msg.sender);
    }

    // ------------------------ reflection distribution ----------------------- //
    /// @notice Called by the hook after it transferred `amount` SPHERE into this contract.
    ///         Distributes those tokens to all reward-eligible holders.
    function distributeReflection(uint256 amount) external onlyHook {
        if (amount == 0) return;
        if (_base[address(this)] < reflectionReserve + amount) revert Unbacked();

        reflectionReserve += amount;
        uint256 toDist = amount + pendingUndistributed;
        pendingUndistributed = 0;

        if (eligibleSupply == 0) {
            pendingUndistributed = toDist; // hold until there are eligible holders
        } else {
            _magPerShare += (toDist * MAG) / eligibleSupply;
            totalReflected += toDist;
        }
        emit ReflectionDistributed(amount, totalReflected);
    }

    // --------------------------- owner config ------------------------------- //
    function setHook(address hook_) external onlyOwner {
        if (hook_ == address(0)) revert ZeroAddress();
        hook = hook_;
        _setExcludedFromLimits(hook_, true);
        _setExcludedFromMaxWallet(hook_, true);
        _setExcludedFromRewards(hook_, true);
        emit HookSet(hook_);
    }

    function enableTrading() external onlyOwner {
        require(!tradingEnabled, "already enabled");
        tradingEnabled = true;
        launchBlock = block.number;
        emit TradingEnabled(block.number);
    }

    function setDeadBlocks(uint256 n) external onlyOwner {
        require(!tradingEnabled, "locked after launch");
        deadBlocks = n;
    }

    /// @notice Remove the 2% max-tx / 2% max-wallet limits.
    function removeLimits() external onlyOwner {
        limitsEnabled = false;
        maxTxAmount = _totalSupplyFixed;
        maxWalletAmount = _totalSupplyFixed;
        emit LimitsRemoved();
    }

    function setMaxLimits(uint256 maxTx, uint256 maxWallet) external onlyOwner {
        require(maxTx >= _totalSupplyFixed / 1000 && maxWallet >= _totalSupplyFixed / 1000, "too low");
        maxTxAmount = maxTx;
        maxWalletAmount = maxWallet;
    }

    function setExcludedFromRewards(address account, bool excluded) external onlyOwner {
        _setExcludedFromRewards(account, excluded);
    }

    function setExcludedFromLimits(address account, bool excluded) external onlyOwner {
        _setExcludedFromLimits(account, excluded);
    }

    function setExcludedFromMaxWallet(address account, bool excluded) external onlyOwner {
        _setExcludedFromMaxWallet(account, excluded);
    }

    /// @notice Exclude/include an address from reflections, max-tx and max-wallet in one call.
    ///         Use for system addresses (PoolManager, PositionManager, routers, treasury).
    ///         The v4 PoolManager MUST be reward-excluded so reflections flow to real holders.
    function excludeFromAll(address account, bool excluded) external onlyOwner {
        _setExcludedFromRewards(account, excluded);
        _setExcludedFromLimits(account, excluded);
        _setExcludedFromMaxWallet(account, excluded);
    }

    // --------------------------- internal: ERC20 ---------------------------- //
    function _approve(address owner_, address spender, uint256 value) internal {
        if (owner_ == address(0) || spender == address(0)) revert ZeroAddress();
        _allowances[owner_][spender] = value;
        emit Approval(owner_, spender, value);
    }

    function _spendAllowance(address owner_, address spender, uint256 value) internal {
        uint256 current = _allowances[owner_][spender];
        if (current != type(uint256).max) {
            require(current >= value, "insufficient allowance");
            unchecked {
                _allowances[owner_][spender] = current - value;
            }
        }
    }

    function _mint(address to, uint256 value) internal {
        _writeBase(to, _base[to] + value);
        emit Transfer(address(0), to, value);
    }

    function _update(address from, address to, uint256 value) internal {
        if (from == address(0) || to == address(0)) revert ZeroAddress();

        _crystallize(from);
        _crystallize(to);

        require(_base[from] >= value, "insufficient balance");

        _checkLimits(from, to, value);

        _writeBase(from, _base[from] - value);
        _writeBase(to, _base[to] + value);

        emit Transfer(from, to, value);
    }

    function _checkLimits(address from, address to, uint256 value) internal view {
        bool fromEx = isExcludedFromLimits[from];
        bool toEx = isExcludedFromLimits[to];

        if (!tradingEnabled && !fromEx && !toEx) revert TradingNotEnabled();

        if (!limitsEnabled) return;

        if (!fromEx && !toEx) {
            if (value > maxTxAmount) revert MaxTxExceeded();
        }
        if (!isExcludedFromMaxWallet[to]) {
            if (_base[to] + value > maxWalletAmount) revert MaxWalletExceeded();
        }
    }

    // ----------------------- internal: reflections -------------------------- //
    function _accumulative(address a) internal view returns (uint256) {
        return uint256(int256(_magPerShare * _base[a]) + _corr[a]) / MAG;
    }

    function _pendingReflection(address a) internal view returns (uint256) {
        return _accumulative(a) - _withdrawn[a];
    }

    /// @dev Sets an account's base balance, maintaining the reflection invariant and
    ///      eligibleSupply for reward-eligible accounts.
    function _writeBase(address a, uint256 newBase) internal {
        uint256 old = _base[a];
        if (newBase == old) return;
        if (!excludedFromRewards[a]) {
            int256 delta = int256(newBase) - int256(old);
            _corr[a] -= int256(_magPerShare) * delta;
            eligibleSupply = uint256(int256(eligibleSupply) + delta);
        }
        _base[a] = newBase;
    }

    /// @dev Moves an account's owed reflections from the reserve into its base balance.
    function _crystallize(address a) internal {
        if (excludedFromRewards[a]) return;
        uint256 p = _pendingReflection(a);
        if (p == 0) return;
        _withdrawn[a] += p;
        reflectionReserve -= p;
        _writeBase(address(this), _base[address(this)] - p);
        _writeBase(a, _base[a] + p);
        emit ReflectionClaimed(a, p);
        emit Transfer(address(this), a, p);
    }

    // ----------------------- internal: exclusions --------------------------- //
    function _setExcludedFromRewards(address a, bool ex) internal {
        if (excludedFromRewards[a] == ex) return;
        if (ex) {
            _crystallize(a);
            eligibleSupply -= _base[a];
            excludedFromRewards[a] = true;
        } else {
            excludedFromRewards[a] = false;
            eligibleSupply += _base[a];
            _corr[a] = -int256(_magPerShare * _base[a]);
            _withdrawn[a] = 0;
        }
        emit ExcludedFromRewards(a, ex);
    }

    function _setExcludedFromLimits(address a, bool ex) internal {
        isExcludedFromLimits[a] = ex;
        emit ExcludedFromLimits(a, ex);
    }

    function _setExcludedFromMaxWallet(address a, bool ex) internal {
        isExcludedFromMaxWallet[a] = ex;
        emit ExcludedFromMaxWallet(a, ex);
    }
}
