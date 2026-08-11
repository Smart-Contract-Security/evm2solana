// SPDX-License-Identifier: GPL-3.0
// OneBalance Bridge Manager Contract
// Part of the OneBalance Framework for managing asset bridging across chains
pragma solidity ^0.8.0;

interface IBridge {
    function lockTokens(address token, uint256 amount, address recipient) external returns (bool);
    function releaseTokens(address token, uint256 amount, address recipient) external returns (bool);
}

contract OneBalanceBridgeManager {
    
    struct BridgeRequest {
        address user;
        address token;
        uint256 amount;
        string destinationChain;
        address recipient;
        bool fulfilled;
    }
    
    mapping(bytes32 => BridgeRequest) private bridgeRequests;
    
    event BridgeRequested(address indexed user, bytes32 bridgeId, address token, uint256 amount, string destinationChain, address recipient);
    event BridgeFulfilled(address indexed user, bytes32 bridgeId);

    function requestBridge(address token, uint256 amount, string memory destinationChain, address recipient) public returns (bytes32) {
        bytes32 bridgeId = keccak256(abi.encodePacked(msg.sender, token, amount, destinationChain, recipient, block.timestamp));
        
        BridgeRequest storage newBridge = bridgeRequests[bridgeId];
        newBridge.user = msg.sender;
        newBridge.token = token;
        newBridge.amount = amount;
        newBridge.destinationChain = destinationChain;
        newBridge.recipient = recipient;
        newBridge.fulfilled = false;
        
        emit BridgeRequested(msg.sender, bridgeId, token, amount, destinationChain, recipient);
        return bridgeId;
    }

    function fulfillBridge(bytes32 bridgeId, address bridgeContract) public {
        BridgeRequest storage bridge = bridgeRequests[bridgeId];
        require(bridge.user != address(0), "Bridge request does not exist");
        require(!bridge.fulfilled, "Bridge already fulfilled");

        require(IBridge(bridgeContract).lockTokens(bridge.token, bridge.amount, bridge.recipient), "Token lock failed");

        bridge.fulfilled = true;
        
        emit BridgeFulfilled(bridge.user, bridgeId);
    }

    function getBridgeDetails(bytes32 bridgeId) public view returns (address, address, uint256, string memory, address, bool) {
        BridgeRequest storage bridge = bridgeRequests[bridgeId];
        return (bridge.user, bridge.token, bridge.amount, bridge.destinationChain, bridge.recipient, bridge.fulfilled);
    }
}