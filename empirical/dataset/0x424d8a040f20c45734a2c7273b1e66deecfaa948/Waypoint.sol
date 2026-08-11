// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

contract Waypoint {

    string public constant name     = "Waypoint";
    string public constant symbol   = "WAPT";
    uint8  public constant decimals = 18;

    uint256 public constant totalSupply = 100_000_000_000_000 * (10 ** 18);

    mapping(address => uint256)                     public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to,       uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor() {
        balanceOf[msg.sender] = totalSupply;
        emit Transfer(address(0), msg.sender, totalSupply);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(to != address(0), "WAPT: transfer to zero address");
        require(balanceOf[msg.sender] >= amount, "WAPT: insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to]         += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        require(spender != address(0), "WAPT: approve to zero address");
        if (amount != 0 && allowance[msg.sender][spender] != 0) {
            allowance[msg.sender][spender] = 0;
            emit Approval(msg.sender, spender, 0);
        }
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) external returns (bool) {
        require(spender != address(0), "WAPT: approve to zero address");
        allowance[msg.sender][spender] += addedValue;
        emit Approval(msg.sender, spender, allowance[msg.sender][spender]);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool) {
        require(spender != address(0), "WAPT: approve to zero address");
        uint256 current = allowance[msg.sender][spender];
        require(current >= subtractedValue, "WAPT: decreased allowance below zero");
        allowance[msg.sender][spender] = current - subtractedValue;
        emit Approval(msg.sender, spender, allowance[msg.sender][spender]);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(to != address(0), "WAPT: transfer to zero address");
        require(balanceOf[from] >= amount, "WAPT: insufficient balance");
        require(allowance[from][msg.sender] >= amount, "WAPT: insufficient allowance");
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to]   += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}