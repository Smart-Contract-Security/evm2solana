// SPDX-License-Identifier: GPL-3.0
// OneBalance Cross-Chain Swap Manager Contract
// Part of the OneBalance Framework for managing cross-chain token swaps
pragma solidity ^0.8.0;

interface IToken {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract OneBalanceCrossChainSwapManager {
    
    struct SwapRequest {
        address user;
        address fromToken;
        address toToken;
        uint256 amount;
        address recipient;
        bool fulfilled;
    }
    
    mapping(bytes32 => SwapRequest) private swapRequests;
    
    event SwapRequested(address indexed user, bytes32 swapId, address fromToken, address toToken, uint256 amount, address recipient);
    event SwapFulfilled(address indexed user, bytes32 swapId);

    function requestSwap(address fromToken, address toToken, uint256 amount, address recipient) public returns (bytes32) {
        bytes32 swapId = keccak256(abi.encodePacked(msg.sender, fromToken, toToken, amount, recipient, block.timestamp));
        
        SwapRequest storage newSwap = swapRequests[swapId];
        newSwap.user = msg.sender;
        newSwap.fromToken = fromToken;
        newSwap.toToken = toToken;
        newSwap.amount = amount;
        newSwap.recipient = recipient;
        newSwap.fulfilled = false;
        
        emit SwapRequested(msg.sender, swapId, fromToken, toToken, amount, recipient);
        return swapId;
    }

    function fulfillSwap(bytes32 swapId) public {
        SwapRequest storage swap = swapRequests[swapId];
        require(swap.user != address(0), "Swap request does not exist");
        require(!swap.fulfilled, "Swap already fulfilled");
        require(IToken(swap.fromToken).transferFrom(swap.user, address(this), swap.amount), "Transfer from user failed");
        require(IToken(swap.toToken).transfer(swap.recipient, swap.amount), "Transfer to recipient failed");

        swap.fulfilled = true;
        
        emit SwapFulfilled(swap.user, swapId);
    }

    function getSwapDetails(bytes32 swapId) public view returns (address, address, address, uint256, address, bool) {
        SwapRequest storage swap = swapRequests[swapId];
        return (swap.user, swap.fromToken, swap.toToken, swap.amount, swap.recipient, swap.fulfilled);
    }
}