// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract MyTokenV1Eth {
    uint8 private constant _DECIMALS = 18;
    uint256[49] private __gap;

    string private _name;
    string private _symbol;
    uint8 private _decimals;
    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    address private _owner;
    bool private _initialized;
    address private _implementation;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Upgraded(address indexed implementation);

    modifier onlyOwner() {
        require(tx.accounts[0].key == _owner, "Ownable: caller is not the owner");
        _;
    }

    modifier initializer() {
        require(!_initialized, "Initializable: contract is already initialized");
        _initialized = true;
        _;
    }

    constructor() {
        _initialized = true;
    }

    function initialize(
        string memory name_,
        string memory symbol_,
        address initialRecipient,
        uint256 initialSupply
    ) public initializer {
        _name = name_;
        _symbol = symbol_;
        _decimals = 18;
        _owner = tx.accounts[0].key;
        emit OwnershipTransferred(address(0), tx.accounts[0].key);

        _mint(initialRecipient, initialSupply);
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public pure returns (uint8) {
        return _DECIMALS;
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        _transfer(tx.accounts[0].key, to, amount);
        return true;
    }

    function allowance(address owner, address spender) public view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        _approve(tx.accounts[0].key, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        uint256 currentAllowance = _allowances[from][tx.accounts[0].key];
        require(currentAllowance >= amount, "ERC20: insufficient allowance");
        _approve(from, tx.accounts[0].key, currentAllowance - amount);
        _transfer(from, to, amount);
        return true;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function renounceOwnership() public onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    function upgradeTo(address newImplementation) public onlyOwner {
        _authorizeUpgrade(newImplementation);
        _implementation = newImplementation;
        emit Upgraded(newImplementation);
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(_balances[from] >= amount, "ERC20: transfer amount exceeds balance");
        _balances[from] -= amount;
        _balances[to] += amount;
        emit Transfer(from, to, amount);
    }

    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: mint to the zero address");
        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    function _approve(address owner_, address spender, uint256 amount) internal {
        require(owner_ != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner_][spender] = amount;
        emit Approval(owner_, spender, amount);
    }

    function _authorizeUpgrade(address newImplementation) internal virtual onlyOwner {}
}