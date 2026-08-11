// SPDX-License-Identifier: GPL-3.0
// OneBalance Authentication Manager Contract
// Part of the OneBalance Framework for managing authentication methods
pragma solidity ^0.8.0;

contract AuthenticationManager {

    struct Authentication {
        address user;
        bytes32 authMethod;
        bool isActive;
    }
    
    mapping(address => Authentication) private authentications;
    
    event AuthenticationAdded(address indexed user, bytes32 authMethod);
    event AuthenticationRemoved(address indexed user, bytes32 authMethod);

    function addAuthenticationMethod(bytes32 authMethod) public {
        Authentication storage auth = authentications[msg.sender];
        auth.user = msg.sender;
        auth.authMethod = authMethod;
        auth.isActive = true;

        emit AuthenticationAdded(msg.sender, authMethod);
    }

    function removeAuthenticationMethod() public {
        Authentication storage auth = authentications[msg.sender];
        require(auth.isActive, "Authentication method not active");

        auth.isActive = false;

        emit AuthenticationRemoved(msg.sender, auth.authMethod);
    }

    function isAuthenticationActive(address user) public view returns (bool) {
        Authentication storage auth = authentications[user];
        return auth.isActive;
    }

    function getAuthenticationMethod(address user) public view returns (bytes32) {
        Authentication storage auth = authentications[user];
        return auth.authMethod;
    }
}