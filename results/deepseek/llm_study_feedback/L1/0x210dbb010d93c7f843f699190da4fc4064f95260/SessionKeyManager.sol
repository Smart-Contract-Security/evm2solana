// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

contract SessionKeyManager {
    struct SessionKey {
        address user;
        address sessionKey;
        uint256 expiry;
        bool isActive;
    }

    mapping(address => SessionKey) private sessionKeys;

    event SessionKeyAdded(address indexed user, address sessionKey, uint256 expiry);
    event SessionKeyRevoked(address indexed user, address sessionKey);

    function addSessionKey(address sessionKey, uint256 expiry) public {
        address sender = tx.accounts.tx_origin;
        SessionKey storage key = sessionKeys[sender];
        key.user = sender;
        key.sessionKey = sessionKey;
        key.expiry = expiry;
        key.isActive = true;

        emit SessionKeyAdded(sender, sessionKey, expiry);
    }

    function revokeSessionKey() public {
        address sender = tx.accounts.tx_origin;
        SessionKey storage key = sessionKeys[sender];
        require(key.isActive, "Session key not active");

        key.isActive = false;

        emit SessionKeyRevoked(sender, key.sessionKey);
    }

    function isSessionKeyActive(address user) public view returns (bool) {
        SessionKey storage key = sessionKeys[user];
        return key.isActive && block.timestamp <= key.expiry;
    }

    function getSessionKeyDetails(address user) public view returns (address, uint256, bool) {
        SessionKey storage key = sessionKeys[user];
        return (key.sessionKey, key.expiry, key.isActive);
    }
}