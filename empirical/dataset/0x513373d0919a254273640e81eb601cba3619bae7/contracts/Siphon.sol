// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title Siphon (SIPHON)
/// @notice Reflective ERC20. Holders receive a pro-rata share of any tokens the
///         configured hook calls `distribute()` with, without anyone iterating
///         the holder set. All distribution math is O(1) — a single SSTORE on
///         the global `cumulativeIndex`. Holders' pending dividends are settled
///         lazily on their next `transfer` / `transferFrom`.
contract Siphon {
    string public constant name = "Siphon";
    string public constant symbol = "SIPHON";
    uint8 public constant decimals = 18;

    uint256 private constant _TOTAL_SUPPLY = 1_000_000 * 1e18;
    uint256 private constant INDEX_SCALE = 1e18;

    address public immutable setupContract;
    address public hook;

    mapping(address => uint256) private _balances;
    mapping(address => uint256) public userIndex;
    mapping(address => bool) public isExcluded;
    mapping(address => mapping(address => uint256)) private _allowances;

    /// @dev Sum of `_balances[a]` over all non-excluded accounts. Denominator
    ///      for distributions. Updated on every cross-boundary transfer and on
    ///      every settle (pending dividends materialize into `_balances`).
    uint256 public nonExcludedSupply;

    /// @dev Per-token dividend accumulator, scaled by INDEX_SCALE.
    uint256 public cumulativeIndex;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Distributed(uint256 amount, uint256 cumulativeIndex);
    event HookSet(address indexed hook);
    event Excluded(address indexed account);

    error NotAuthorized();
    error HookAlreadySet();
    error ZeroAddress();
    error InsufficientBalance();
    error InsufficientAllowance();

    /// @param _setupContract Address of the SiphonSetup contract. Receives the
    ///        entire initial supply and is the only address allowed to call
    ///        `setHook` / `excludeFromReflections`.
    constructor(address _setupContract) {
        if (_setupContract == address(0)) revert ZeroAddress();
        setupContract = _setupContract;
        _balances[_setupContract] = _TOTAL_SUPPLY;
        nonExcludedSupply = _TOTAL_SUPPLY;
        emit Transfer(address(0), _setupContract, _TOTAL_SUPPLY);
    }

    function totalSupply() external pure returns (uint256) {
        return _TOTAL_SUPPLY;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account] + _pendingOf(account);
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 value) external returns (bool) {
        _allowances[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 allowed = _allowances[from][msg.sender];
        if (allowed != type(uint256).max) {
            if (allowed < value) revert InsufficientAllowance();
            unchecked { _allowances[from][msg.sender] = allowed - value; }
        }
        _transfer(from, to, value);
        return true;
    }

    /// @notice Called by the hook to credit every non-excluded holder a
    ///         pro-rata share of `amount`. O(1) — no holder iteration.
    function distribute(uint256 amount) external {
        if (msg.sender != hook) revert NotAuthorized();
        if (amount == 0) return;
        uint256 supply = nonExcludedSupply;
        if (supply == 0) return; // nothing to distribute to; leave in hook
        uint256 bal = _balances[hook];
        if (bal < amount) revert InsufficientBalance();
        uint256 delta = (amount * INDEX_SCALE) / supply;
        if (delta == 0) return; // dust; leave in hook so it accumulates
        // Burn exactly what we credit via the index, so totalSupply is conserved
        // to the wei. Any remainder (amount - actual) stays in the hook for the
        // next distribute.
        uint256 actual = (delta * supply) / INDEX_SCALE;
        unchecked {
            _balances[hook] = bal - actual;
            cumulativeIndex += delta;
        }
        emit Distributed(actual, cumulativeIndex);
    }

    /// @notice One-shot wiring of the hook. Called by SiphonSetup.
    function setHook(address _hook) external {
        if (msg.sender != setupContract) revert NotAuthorized();
        if (hook != address(0)) revert HookAlreadySet();
        if (_hook == address(0)) revert ZeroAddress();
        hook = _hook;
        _exclude(_hook);
        emit HookSet(_hook);
    }

    /// @notice Exclude an address (e.g. V4 PoolManager) from reflections so
    ///         distributed tokens don't leak into pool reserves.
    function excludeFromReflections(address account) external {
        if (msg.sender != setupContract) revert NotAuthorized();
        _exclude(account);
    }

    function _pendingOf(address account) internal view returns (uint256) {
        if (isExcluded[account]) return 0;
        uint256 diff;
        unchecked { diff = cumulativeIndex - userIndex[account]; }
        if (diff == 0) return 0;
        return (_balances[account] * diff) / INDEX_SCALE;
    }

    function _settle(address account) internal {
        if (isExcluded[account]) return;
        uint256 idx = cumulativeIndex;
        if (userIndex[account] == idx) return;
        uint256 bal = _balances[account];
        if (bal != 0) {
            uint256 pending;
            unchecked { pending = (bal * (idx - userIndex[account])) / INDEX_SCALE; }
            if (pending != 0) {
                unchecked {
                    _balances[account] = bal + pending;
                    nonExcludedSupply += pending;
                }
            }
        }
        userIndex[account] = idx;
    }

    function _transfer(address from, address to, uint256 value) internal {
        if (to == address(0)) revert ZeroAddress();
        _settle(from);
        _settle(to);
        uint256 fromBal = _balances[from];
        if (fromBal < value) revert InsufficientBalance();
        bool fromEx = isExcluded[from];
        bool toEx = isExcluded[to];
        unchecked {
            _balances[from] = fromBal - value;
            _balances[to] += value;
        }
        if (fromEx != toEx) {
            unchecked {
                if (fromEx) nonExcludedSupply += value;
                else nonExcludedSupply -= value;
            }
        }
        emit Transfer(from, to, value);
    }

    function _exclude(address account) internal {
        if (isExcluded[account]) return;
        _settle(account);
        isExcluded[account] = true;
        uint256 bal = _balances[account];
        if (bal != 0) {
            unchecked { nonExcludedSupply -= bal; }
        }
        emit Excluded(account);
    }
}
