// SPDX-License-Identifier: GPL-3.0
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
        address sender = tx.accounts.data[0].key;
        bytes32 lockId = keccak256(abi.encodePacked(sender, amount, conditions, expiry, block.timestamp));
        
        resourceLocks[lockId] = ResourceLock({
            owner: sender,
            amount: amount,
            conditions: conditions,
            expiry: expiry,
            fulfilled: false
        });
        
        emit ResourceLockCreated(sender, lockId, amount, conditions, expiry);
        return lockId;
    }

    function fulfillResourceLock(bytes32 lockId, bytes32 proof) public {
        ResourceLock storage lock = resourceLocks[lockId];
        address sender = tx.accounts.data[0].key;
        require(lock.owner == sender, "Only the owner can fulfill the lock");
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