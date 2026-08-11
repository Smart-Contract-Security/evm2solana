// Solana port of Token contract using Solang
pragma solidity ^0.8.2;

import 'solana';

contract Token {
    mapping(address => uint) public balances;
    mapping(address => mapping(address => uint)) public allowance;
    uint public totalSupply = 1500000000000 * 10 ** 18;
    string public name = "Bondex";
    string public symbol = "BDXN";
    uint public decimals = 18;

    event Transfer(address indexed from, address indexed to, uint value);
    event Approval(address indexed owner, address indexed spender, uint value);

    @payer(payer)
    @space(512 + 32 * 3)
    constructor(address payer) {
        balances[tx.accounts.payer.key] = totalSupply;
    }

    function balanceOf(address owner) public view returns(uint) {
        return balances[owner];
    }

    function transfer(address to, uint value) public returns(bool) {
        require(balances[tx.accounts.transaction_authority.key] >= value, 'balance too low');
        balances[to] += value;
        balances[tx.accounts.transaction_authority.key] -= value;
        emit Transfer(tx.accounts.transaction_authority.key, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint value) public returns(bool) {
        require(balances[from] >= value, 'balance too low');
        require(allowance[from][tx.accounts.transaction_authority.key] >= value, 'allowance too low');
        balances[to] += value;
        balances[from] -= value;
        emit Transfer(from, to, value);
        return true;
    }

    function approve(address spender, uint value) public returns (bool) {
        allowance[tx.accounts.transaction_authority.key][spender] = value;
        emit Approval(tx.accounts.transaction_authority.key, spender, value);
        return true;
    }
}