// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MyToken {
    string public name = "Metalarge";
    string public symbol = "MTL";
    uint8 public decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    address public owner;

    constructor(uint256 initialSupply) {
        owner = tx.accounts[0];
        totalSupply = initialSupply * (10 ** uint256(decimals));
        balanceOf[owner] = totalSupply;
        emit Transfer(address(0), owner, totalSupply);
    }

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function transfer(address to, uint256 value) public returns (bool success) {
        require(balanceOf[tx.accounts[0]] >= value, "insufficient balance");
        _transfer(tx.accounts[0], to, value);
        return true;
    }

    function _transfer(address from, address to, uint256 value) internal {
        require(to != address(0), "invalid to address");
        balanceOf[from] -= value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
    }

    function approve(address spender, uint256 value) public returns (bool success) {
        allowance[tx.accounts[0]][spender] = value;
        emit Approval(tx.accounts[0], spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) public returns (bool success) {
        require(value <= balanceOf[from], "insufficient balance");
        require(value <= allowance[from][tx.accounts[0]], "insufficient allowance");
        allowance[from][tx.accounts[0]] -= value;
        _transfer(from, to, value);
        return true;
    }
}