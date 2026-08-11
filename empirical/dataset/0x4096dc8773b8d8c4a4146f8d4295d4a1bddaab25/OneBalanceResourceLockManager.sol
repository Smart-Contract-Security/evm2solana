// SPDX-License-Identifier: GPL-3.0
// OneBalance Resource Lock Manager Contract
// Part of the OneBalance Framework for managing resource locks
pragma solidity ^0.8.0;

contract OneBalanceResourceLockManager {
    
    struct ResourceLock {
        address owner;
        uint256 amount;
        bytes32 conditions;
        uint256 expiry;
        bool fulfilled;
    }
    
    mapping(bytes32 => ResourceLock) private resourceLocks;
    
    event ResourceLockCreated(address indexed owner, bytes32 lockId, uint256 amount, bytes32 conditions, uint256 expiry);
    event ResourceLockFulfilled(address indexed owner, bytes32 lockId);

    function createResourceLock(uint256 amount, bytes32 conditions, uint256 expiry) public returns (bytes32) {
        bytes32 lockId = keccak256(abi.encodePacked(msg.sender, amount, conditions, expiry, block.timestamp));
        
        ResourceLock storage newLock = resourceLocks[lockId];
        newLock.owner = msg.sender;
        newLock.amount = amount;
        newLock.conditions = conditions;
        newLock.expiry = expiry;
        newLock.fulfilled = false;
        
        emit ResourceLockCreated(msg.sender, lockId, amount, conditions, expiry);
        return lockId;
    }

    function fulfillResourceLock(bytes32 lockId, bytes32 proof) public {
        ResourceLock storage lock = resourceLocks[lockId];
        require(lock.owner == msg.sender, "Only the owner can fulfill the lock");
        require(!lock.fulfilled, "Lock already fulfilled");
        require(block.timestamp <= lock.expiry, "Lock expired");

        require(validateProof(proof), "Invalid proof");

        lock.fulfilled = true;
        
        emit ResourceLockFulfilled(lock.owner, lockId);
    }

    function getLockDetails(bytes32 lockId) public view returns (address, uint256, bytes32, uint256, bool) {
        ResourceLock storage lock = resourceLocks[lockId];
        return (lock.owner, lock.amount, lock.conditions, lock.expiry, lock.fulfilled);
    }

    function validateProof(bytes32 proof) internal pure returns (bool) {
        return proof != bytes32(0);
    }
}