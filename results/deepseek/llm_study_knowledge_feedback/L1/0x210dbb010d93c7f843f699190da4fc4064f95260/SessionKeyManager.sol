@program_id("SessionKeyManager1111111111111111111111111")
contract SessionKeyManager {

    struct SessionKey {
        address user;
        address sessionKey;
        uint64 expiry;
        bool isActive;
    }
    
    mapping(address => SessionKey) private sessionKeys;
    
    event SessionKeyAdded(address user, address sessionKey, uint64 expiry);
    event SessionKeyRevoked(address user, address sessionKey);

    function addSessionKey(address sessionKey, uint64 expiry) public {
        SessionKey storage key = sessionKeys[tx.accounts.dataAccount.key];
        key.user = tx.accounts.dataAccount.key;
        key.sessionKey = sessionKey;
        key.expiry = expiry;
        key.isActive = true;

        emit SessionKeyAdded(tx.accounts.dataAccount.key, sessionKey, expiry);
    }

    function revokeSessionKey() public {
        SessionKey storage key = sessionKeys[tx.accounts.dataAccount.key];
        require(key.isActive, "Session key not active");

        key.isActive = false;

        emit SessionKeyRevoked(tx.accounts.dataAccount.key, key.sessionKey);
    }

    function isSessionKeyActive(address user) public view returns (bool) {
        SessionKey storage key = sessionKeys[user];
        return key.isActive && block.timestamp <= key.expiry;
    }

    function getSessionKeyDetails(address user) public view returns (address, uint64, bool) {
        SessionKey storage key = sessionKeys[user];
        return (key.sessionKey, key.expiry, key.isActive);
    }
}