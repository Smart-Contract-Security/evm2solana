// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

contract FRASK {
    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public allowance;
    
    uint256 public totalSupply = 1000000000 * 10 ** 18;
    string public name = "Frog wif mask";
    string public symbol = "FRASK";
    uint256 public decimals = 18;
    
    address public owner;
    bool public paused;
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Mint(address indexed to, uint256 amount);
    event Burn(address indexed from, uint256 amount);
    
    constructor() {
        owner = msg.sender;
        balances[msg.sender] = totalSupply;
        emit Transfer(address(0), msg.sender, totalSupply);  // Added this event
    }
    
    function transfer(address to, uint256 value) public returns(bool) {
        require(balances[msg.sender] >= value, "Not enough tokens");
        require(to != address(0), "Invalid address");
        
        balances[msg.sender] = balances[msg.sender] - value;
        balances[to] = balances[to] + value;
        
        emit Transfer(msg.sender, to, value);
        return true;
    }
    
    function balanceOf(address account) public view returns(uint256) {
        return balances[account];
    }
    
    function approve(address spender, uint256 value) public returns(bool) {
        require(spender != address(0), "Invalid address");
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 value) public returns(bool) {
        require(value <= balances[from], "Not enough tokens");
        require(value <= allowance[from][msg.sender], "Not approved");
        
        balances[from] = balances[from] - value;
        balances[to] = balances[to] + value;
        allowance[from][msg.sender] = allowance[from][msg.sender] - value;
        
        emit Transfer(from, to, value);
        return true;
    }
    
    function burn(uint256 value) public returns(bool) {
        require(balances[msg.sender] >= value, "Not enough tokens");
        balances[msg.sender] = balances[msg.sender] - value;
        totalSupply = totalSupply - value;
        emit Transfer(msg.sender, address(0), value);
        emit Burn(msg.sender, value);
        return true;
    }
    
    function mint(address to, uint256 amount) public onlyOwner returns(bool) {
        require(to != address(0), "Invalid address");
        totalSupply = totalSupply + amount;
        balances[to] = balances[to] + amount;
        emit Transfer(address(0), to, amount);
        emit Mint(to, amount);
        return true;
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }
}