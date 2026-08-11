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
        SessionKey storage key = sessionKeys[msg.sender];
        key.user = msg.sender;
        key.sessionKey = sessionKey;
        key.expiry = expiry;
        key.isActive = true;

        emit SessionKeyAdded(msg.sender, sessionKey, expiry);
    }

    function revokeSessionKey() public {
        SessionKey storage key = sessionKeys[msg.sender];
        require(key.isActive, "Session key not active");

        key.isActive = false;

        emit SessionKeyRevoked(msg.sender, key.sessionKey);
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