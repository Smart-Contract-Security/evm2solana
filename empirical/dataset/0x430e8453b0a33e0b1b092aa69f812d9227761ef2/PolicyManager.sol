// SPDX-License-Identifier: GPL-3.0
// OneBalance Policy Manager Contract
// Part of the OneBalance Framework for managing policies over user accounts
pragma solidity ^0.8.0;

contract PolicyManager {

    struct Policy {
        address user;
        bytes32 policyId;
        bytes32 conditions;
        bool isActive;
    }
    
    mapping(address => mapping(bytes32 => Policy)) private policies;
    
    event PolicyAdded(address indexed user, bytes32 policyId, bytes32 conditions);
    event PolicyRemoved(address indexed user, bytes32 policyId);

    function addPolicy(bytes32 policyId, bytes32 conditions) public {
        Policy storage newPolicy = policies[msg.sender][policyId];
        newPolicy.user = msg.sender;
        newPolicy.policyId = policyId;
        newPolicy.conditions = conditions;
        newPolicy.isActive = true;

        emit PolicyAdded(msg.sender, policyId, conditions);
    }

    function removePolicy(bytes32 policyId) public {
        Policy storage policy = policies[msg.sender][policyId];
        require(policy.isActive, "Policy not active");

        policy.isActive = false;

        emit PolicyRemoved(msg.sender, policyId);
    }

    function isPolicyActive(address user, bytes32 policyId) public view returns (bool) {
        Policy storage policy = policies[user][policyId];
        return policy.isActive;
    }

    function getPolicyDetails(address user, bytes32 policyId) public view returns (bytes32, bytes32, bool) {
        Policy storage policy = policies[user][policyId];
        return (policy.policyId, policy.conditions, policy.isActive);
    }
}