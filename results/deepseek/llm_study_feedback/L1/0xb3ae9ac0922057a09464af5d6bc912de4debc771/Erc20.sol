// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address who) external view returns (uint256);
    function allowance(address _owner, address spender) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return tx.origin;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

contract Erc20 is Context, IERC20 {
    mapping(address => uint256) internal _balances;
    mapping(address => mapping(address => uint256)) internal _allowed;

    uint256 public totalSupply;
    string public symbol;
    string public name;
    uint8 public decimals;

    constructor(string memory _symbol, string memory _name, uint8 _decimals, uint256 _totalSupply) {
        symbol = _symbol;
        name = _name;
        decimals = _decimals;
        totalSupply = _totalSupply;
        _balances[tx.origin] += _totalSupply;
        emit Transfer(address(0), tx.origin, _totalSupply);
    }

    function balanceOf(address _owner) external view override returns (uint256) {
        return _balances[_owner];
    }

    function allowance(address _owner, address spender) external view override returns (uint256) {
        return _allowed[_owner][spender];
    }

    function transfer(address to, uint256 value) external override returns (bool) {
        _transfer(tx.origin, to, value);
        return true;
    }

    function approve(address spender, uint256 value) external override returns (bool) {
        require(spender != address(0), "cannot approve the 0 address");
        _allowed[tx.origin][spender] = value;
        emit Approval(tx.origin, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external override returns (bool) {
        _allowed[from][tx.origin] = _allowed[from][tx.origin] - value;
        _transfer(from, to, value);
        emit Approval(from, tx.origin, _allowed[from][tx.origin]);
        return true;
    }

    function _transfer(address from, address to, uint256 value) private {
        require(to != address(0), "cannot be zero address");
        require(from != to, "you cannot transfer to yourself");
        _balances[from] -= value;
        _balances[to] += value;
        emit Transfer(from, to, value);
    }
}