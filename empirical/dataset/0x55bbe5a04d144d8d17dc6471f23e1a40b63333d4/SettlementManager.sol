// SPDX-License-Identifier: GPL-3.0
// OneBalance Settlement Manager Contract
// Part of the OneBalance Framework for managing the settlement of transactions on-chain
pragma solidity ^0.8.0;

contract SettlementManager {

    struct Settlement {
        address user;
        bytes32 transactionId;
        bool settled;
    }
    
    mapping(bytes32 => Settlement) private settlements;
    
    event SettlementRequested(address indexed user, bytes32 transactionId);
    event SettlementCompleted(address indexed user, bytes32 transactionId);

    function requestSettlement(bytes32 transactionId) public returns (bytes32) {
        bytes32 settlementId = keccak256(abi.encodePacked(msg.sender, transactionId, block.timestamp));
        
        Settlement storage newSettlement = settlements[settlementId];
        newSettlement.user = msg.sender;
        newSettlement.transactionId = transactionId;
        newSettlement.settled = false;
        
        emit SettlementRequested(msg.sender, transactionId);
        return settlementId;
    }

    function completeSettlement(bytes32 settlementId) public {
        Settlement storage settlement = settlements[settlementId];
        require(settlement.user != address(0), "Settlement request does not exist");
        require(!settlement.settled, "Settlement already completed");

        settlement.settled = true;
        
        emit SettlementCompleted(settlement.user, settlement.transactionId);
    }

    function getSettlementDetails(bytes32 settlementId) public view returns (address, bytes32, bool) {
        Settlement storage settlement = settlements[settlementId];
        return (settlement.user, settlement.transactionId, settlement.settled);
    }
}