// SPDX-License-Identifier: GPL-3.0
// OneBalance Fulfillment Engine Contract
// Part of the OneBalance Framework for managing fulfillment of resource locks and state transitions
pragma solidity ^0.8.0;

contract FulfillmentEngine {

    struct Fulfillment {
        address owner;
        bytes32 lockId;
        bytes32 proof;
        bool fulfilled;
    }
    
    mapping(bytes32 => Fulfillment) private fulfillments;
    
    event FulfillmentRequested(address indexed owner, bytes32 lockId, bytes32 fulfillmentId);
    event FulfillmentCompleted(address indexed owner, bytes32 lockId, bytes32 fulfillmentId);

    function requestFulfillment(bytes32 lockId, bytes32 proof) public returns (bytes32) {
        bytes32 fulfillmentId = keccak256(abi.encodePacked(msg.sender, lockId, proof, block.timestamp));
        
        Fulfillment storage newFulfillment = fulfillments[fulfillmentId];
        newFulfillment.owner = msg.sender;
        newFulfillment.lockId = lockId;
        newFulfillment.proof = proof;
        newFulfillment.fulfilled = false;
        
        emit FulfillmentRequested(msg.sender, lockId, fulfillmentId);
        return fulfillmentId;
    }

    function completeFulfillment(bytes32 fulfillmentId) public {
        Fulfillment storage fulfillment = fulfillments[fulfillmentId];
        require(fulfillment.owner != address(0), "Fulfillment request does not exist");
        require(!fulfillment.fulfilled, "Fulfillment already completed");

        require(validateProof(fulfillment.proof), "Invalid proof");

        fulfillment.fulfilled = true;
        
        emit FulfillmentCompleted(fulfillment.owner, fulfillment.lockId, fulfillmentId);
    }

    function getFulfillmentDetails(bytes32 fulfillmentId) public view returns (address, bytes32, bytes32, bool) {
        Fulfillment storage fulfillment = fulfillments[fulfillmentId];
        return (fulfillment.owner, fulfillment.lockId, fulfillment.proof, fulfillment.fulfilled);
    }

    function validateProof(bytes32 proof) internal pure returns (bool) {
        return proof != bytes32(0);
    }
}