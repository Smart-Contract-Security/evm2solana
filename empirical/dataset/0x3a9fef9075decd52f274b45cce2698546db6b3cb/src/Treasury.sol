// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Treasury
 * @notice Holds dev fees from bonding curve
 */
contract Treasury is Ownable, ReentrancyGuard {
    event ETHWithdrawn(address indexed to, uint256 amount);
    event TokenWithdrawn(address indexed token, address indexed to, uint256 amount);
    
    constructor() Ownable(msg.sender) {}
    
    /**
     * @notice Withdraw all ETH to owner
     */
    function withdrawETH() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH to withdraw");
        
        (bool success, ) = owner().call{value: balance}("");
        require(success, "ETH transfer failed");
        
        emit ETHWithdrawn(owner(), balance);
    }
    
    /**
     * @notice Withdraw specific amount of ERC20 tokens
     * @param token Token address
     * @param to Recipient address
     * @param amount Amount to withdraw
     */
    function withdrawToken(address token, address to, uint256 amount) external onlyOwner nonReentrant {
        require(token != address(0), "Invalid token address");
        require(to != address(0), "Invalid recipient address");
        require(amount > 0, "Amount must be > 0");
        
        IERC20 tokenContract = IERC20(token);
        uint256 balance = tokenContract.balanceOf(address(this));
        require(amount <= balance, "Insufficient token balance");
        
        require(tokenContract.transfer(to, amount), "Token transfer failed");
        
        emit TokenWithdrawn(token, to, amount);
    }
    
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
    
    function getTokenBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }
    
    receive() external payable {}
}
