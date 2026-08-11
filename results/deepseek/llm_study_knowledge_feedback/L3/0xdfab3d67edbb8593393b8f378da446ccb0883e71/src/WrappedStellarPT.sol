// SPDX-License-Identifier: BUSL-1.1

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title WrappedStellarPT
 * @notice ERC20 representation of a Stellar-native Principal Token on EVM
 * @dev Deployed by PTBridge via BeaconProxy + CREATE2 when a native Stellar PT is first bridged.
 *      Only the bridge can mint (on lock) and burn (on unlock).
 *      Uses Beacon Proxy pattern: all instances share one implementation, upgradeable in one tx.
 */
contract WrappedStellarPT is Initializable {
    // ERC20 state variables
    mapping(address => uint64) private _balances;
    mapping(address => mapping(address => uint64)) private _allowances;
    uint64 private _totalSupply;
    string private _name;
    string private _symbol;

    uint8 private _decimals;
    uint64 public maturity;
    string public stellarPtAddress;
    address public bridge;

    event Transfer(address indexed from, address indexed to, uint64 value);
    event Approval(address indexed owner, address indexed spender, uint64 value);

    modifier onlyBridge() {
        require(tx.accounts.dataAccount.key == bridge, "OnlyBridge");
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint64 maturity_,
        string memory stellarPtAddress_,
        address bridge_
    ) external initializer {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
        maturity = maturity_;
        stellarPtAddress = stellarPtAddress_;
        bridge = bridge_;
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view returns (uint64) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint64) {
        return _balances[account];
    }

    function transfer(address to, uint64 amount) public returns (bool) {
        address owner = tx.accounts.dataAccount.key;
        _transfer(owner, to, amount);
        return true;
    }

    function allowance(address owner, address spender) public view returns (uint64) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint64 amount) public returns (bool) {
        address owner = tx.accounts.dataAccount.key;
        _approve(owner, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint64 amount) public returns (bool) {
        address spender = tx.accounts.dataAccount.key;
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function increaseAllowance(address spender, uint64 addedValue) public returns (bool) {
        address owner = tx.accounts.dataAccount.key;
        _approve(owner, spender, _allowances[owner][spender] + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint64 subtractedValue) public returns (bool) {
        address owner = tx.accounts.dataAccount.key;
        uint64 currentAllowance = _allowances[owner][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(owner, spender, currentAllowance - subtractedValue);
        }
        return true;
    }

    function _transfer(address from, address to, uint64 amount) internal {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        uint64 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[from] = fromBalance - amount;
        }
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
        uint64 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint64).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }

    function _mint(address account, uint64 amount) internal {
        require(account != address(0), "ERC20: mint to the zero address");
        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint64 amount) internal {
        require(account != address(0), "ERC20: burn from the zero address");
        uint64 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
        }
        _totalSupply -= amount;
        emit Transfer(account, address(0), amount);
    }

    function mint(address to, uint64 amount) external onlyBridge {
        _mint(to, amount);
    }

    function burn(address from, uint64 amount) external onlyBridge {
        _burn(from, amount);
    }
}