@program_id("1Ba1ResLockMgr11111111111111111111111111111")
contract OneBalanceResourceLockManager {
    
    struct ResourceLock {
        address owner;
        uint64 amount;
        bytes32 conditions;
        uint64 expiry;
        bool fulfilled;
    }
    
    mapping(bytes32 => ResourceLock) private resourceLocks;
    
    event ResourceLockCreated(address owner, bytes32 lockId, uint64 amount, bytes32 conditions, uint64 expiry);
    event ResourceLockFulfilled(address owner, bytes32 lockId);

    function createResourceLock(uint64 amount, bytes32 conditions, uint64 expiry) public returns (bytes32) {
        bytes32 lockId = keccak256(abi.encodePacked(tx.accounts.dataAccount.key, amount, conditions, expiry, block.timestamp));
        
        ResourceLock storage newLock = resourceLocks[lockId];
        newLock.owner = tx.accounts.dataAccount.key;
        newLock.amount = amount;
        newLock.conditions = conditions;
        newLock.expiry = expiry;
        newLock.fulfilled = false;
        
        emit ResourceLockCreated(tx.accounts.dataAccount.key, lockId, amount, conditions, expiry);
        return lockId;
    }

    function fulfillResourceLock(bytes32 lockId, bytes32 proof) public {
        ResourceLock storage lock = resourceLocks[lockId];
        require(lock.owner == tx.accounts.dataAccount.key, "Only the owner can fulfill the lock");
        require(!lock.fulfilled, "Lock already fulfilled");
        require(block.timestamp <= lock.expiry, "Lock expired");

        require(validateProof(proof), "Invalid proof");

        lock.fulfilled = true;
        
        emit ResourceLockFulfilled(lock.owner, lockId);
    }

    function getLockDetails(bytes32 lockId) public view returns (address, uint64, bytes32, uint64, bool) {
        ResourceLock storage lock = resourceLocks[lockId];
        return (lock.owner, lock.amount, lock.conditions, lock.expiry, lock.fulfilled);
    }

    function validateProof(bytes32 proof) internal pure returns (bool) {
        return proof != bytes32(0);
    }
}