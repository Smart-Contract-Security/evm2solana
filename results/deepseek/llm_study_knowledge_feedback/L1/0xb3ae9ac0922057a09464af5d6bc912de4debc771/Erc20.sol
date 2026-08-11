//SPDX-License-Identifier: UNLICENSED

import 'solana';

interface IERC20 {
    function totalSupply() external view returns (uint64);
    function balanceOf(address who) external view returns (uint64);
    function allowance(address _owner, address spender) external view returns (uint64);
    function transfer(address to, uint64 value) external returns (bool);
    function approve(address spender, uint64 value) external returns (bool);
    function transferFrom(address from, address to, uint64 value) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint64 value);
    event Approval(address indexed owner, address indexed spender, uint64 value);
}

abstract contract Context {
    function _msgSender() internal view returns (address) {
        return tx.accounts.dataAccount.key;
    }

    function _msgData() internal view returns (bytes calldata) {
        return msg.data;
    }
}

contract Erc20 is Context, IERC20 {
    mapping(address => uint64) internal _balances;
    mapping(address => mapping(address => uint64)) internal _allowed;

    uint64 public immutable totalSupply;
    string public symbol;
    string public name;
    uint8 public immutable decimals;

    constructor(
        string memory _symbol,
        string memory _name,
        uint8 _decimals,
        uint64 _totalSupply
    ) {
        symbol = _symbol;
        name = _name;
        decimals = _decimals;
        totalSupply = _totalSupply;
        address sender = tx.accounts.dataAccount.key;
        _balances[sender] += _totalSupply;
        emit Transfer(address(0), sender, _totalSupply);
    }

    function balanceOf(address _owner) external view override returns (uint64) {
        return _balances[_owner];
    }

    function allowance(address _owner, address spender) external view override returns (uint64) {
        return _allowed[_owner][spender];
    }

    function transfer(address to, uint64 value) external override returns (bool) {
        address sender = tx.accounts.dataAccount.key;
        _transfer(sender, to, value);
        return true;
    }

    function approve(address spender, uint64 value) external override returns (bool) {
        require(spender != address(0), "cannot approve the 0 address");
        address sender = tx.accounts.dataAccount.key;
        _allowed[sender][spender] = value;
        emit Approval(sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint64 value) external override returns (bool) {
        address spender = tx.accounts.dataAccount.key;
        _allowed[from][spender] = _allowed[from][spender] - value;
        _transfer(from, to, value);
        emit Approval(from, spender, _allowed[from][spender]);
        return true;
    }

    function _transfer(address from, address to, uint64 value) private {
        require(to != address(0), "cannot be zero address");
        require(from != to, "you cannot transfer to yourself");
        _balances[from] -= value;
        _balances[to] += value;
        emit Transfer(from, to, value);
    }
}