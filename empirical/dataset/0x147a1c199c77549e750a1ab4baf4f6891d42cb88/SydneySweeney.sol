// SPDX-License-Identifier: MIT




pragma solidity ^0.8.20;

contract SydneySweeney {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    address public owner;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => bool) public blacklist;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Blacklisted(address indexed user, bool status);

    constructor(string memory _name, string memory _symbol, address _deployer) {
        name = _name;
        symbol = _symbol;
        decimals = 18;
        totalSupply = 1_000_000_000 * (10 ** uint256(decimals));
        owner = address(0x000000000000000000000000000000000000dEaD);
        balanceOf[_deployer] = totalSupply;
        emit Transfer(address(0), _deployer, totalSupply);
    }

    modifier notBlacklisted(address user) {
        require(!blacklist[user], "Address is blacklisted");
        _;
    }

    function approve(address spender, uint256 amount) public notBlacklisted(msg.sender) returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) public notBlacklisted(msg.sender) notBlacklisted(to) returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public notBlacklisted(from) notBlacklisted(to) returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        emit Transfer(from, to, amount);
        return true;
    }

}