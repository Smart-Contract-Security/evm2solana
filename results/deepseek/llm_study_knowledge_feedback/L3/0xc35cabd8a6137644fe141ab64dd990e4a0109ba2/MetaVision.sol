// SPDX-License-Identifier: MIT

import 'solana';

contract MetaVision {
    address private _owner;
    string public name = "MetaVision";
    string public symbol = "MV";
    uint8 public decimals = 9;
    uint64 public totalSupply;
    bool public tradingOpen = false;

    mapping(address => uint64) private _balances;
    mapping(address => mapping(address => uint64)) private _allowances;

    event Transfer(address indexed from, address indexed to, uint64 value);
    event Approval(address indexed owner, address indexed spender, uint64 value);

    modifier onlyOwner() {
        require(tx.accounts.dataAccount.key == _owner, "Not owner");
        _;
    }

    constructor() {
        _owner = tx.accounts.dataAccount.key;
        uint64 initialSupply = 1000000000 * 10 ** uint64(decimals);
        _mint(_owner, initialSupply);
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

    function openTrading() external onlyOwner {
        tradingOpen = true;
    }

    function _transfer(address from, address to, uint64 amount) internal {
        require(from != address(0), "ERC20: transfer from zero");
        require(to != address(0), "ERC20: transfer to zero");
        _beforeTokenTransfer(from, to, amount);
        uint64 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC20: insufficient balance");
        _balances[from] = fromBalance - amount;
        _balances[to] += amount;
        emit Transfer(from, to, amount);
    }

    function _mint(address account, uint64 amount) internal {
        require(account != address(0), "ERC20: mint to zero");
        totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    function _approve(address owner, address spender, uint64 amount) internal {
        require(owner != address(0), "ERC20: approve from zero");
        require(spender != address(0), "ERC20: approve to zero");
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

    function _beforeTokenTransfer(address from, address to, uint64 amount) internal view {
        if (!tradingOpen) {
            require(from == _owner || to == _owner, "Prekyba dar neaktyvuota! (Anti-Sniper atmetimas)");
        }
    }

    function owner() public view returns (address) {
        return _owner;
    }
}