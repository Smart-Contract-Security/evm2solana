pragma solidity ^0.8.2;

contract Token {
    mapping(address => uint) public balances;
    mapping(address => mapping(address => uint)) public allowance;
    uint public totalSupply = 1500000000000 * 10 ** 18;
    string public name = "Bondex";
    string public symbol = "BDXN";
    uint public decimals = 18;

    event Transfer(address indexed from, address indexed to, uint value);
    event Approval(address indexed owner, address indexed spender, uint value);

    address private _owner;

    constructor() {
        _owner = tx.accounts[0].key;
        balances[_owner] = totalSupply;
    }

    function balanceOf(address owner) public view returns(uint) {
        return balances[owner];
    }

    function transfer(address to, uint value) public returns(bool) {
        address sender = tx.accounts[0].key;
        require(balanceOf(sender) >= value, 'balance too low');
        balances[to] += value;
        balances[sender] -= value;
        emit Transfer(sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint value) public returns(bool) {
        address spender = tx.accounts[0].key;
        require(balanceOf(from) >= value, 'balance too low');
        require(allowance[from][spender] >= value, 'allowance too low');
        balances[to] += value;
        balances[from] -= value;
        emit Transfer(from, to, value);
        return true;
    }

    function approve(address spender, uint value) public returns (bool) {
        address owner = tx.accounts[0].key;
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
        return true;
    }
}