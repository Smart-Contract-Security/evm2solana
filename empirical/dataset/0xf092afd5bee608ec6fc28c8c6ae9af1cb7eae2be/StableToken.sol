// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract StableToken {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    uint256 public constant USD_PRICE = 100; // Example: 1 USD = 100 units

    constructor() {
        name = "Trade_Bonds";
        symbol = "TSDT";
        decimals = 18;
        totalSupply = 987654321987654321987654321000000000 * USD_PRICE;
    }

    function mint(address to, uint256 amount) public {
        uint256 tokenAmount = amount * USD_PRICE;
        balanceOf[to] += tokenAmount;
        totalSupply += tokenAmount;
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        require(balanceOf[msg.sender] >= amount);
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        require(balanceOf[from] >= amount && allowance[from][msg.sender] >= amount);
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        return true;
    }
    
}