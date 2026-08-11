// OneBalance Credible Account Manager Contract
// Part of the OneBalance Framework for managing Credible Accounts
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

contract OneBalanceCredibleAccountManager {
    
    struct Account {
        address owner;
        bytes32 state;
        mapping(address => bool) permissions;
    }
    
    mapping(address => Account) private accounts;
    
    event AccountCreated(address indexed owner, bytes32 state);
    event PermissionSet(address indexed owner, address indexed permission, bool status);

    function createCredibleAccount(address user, bytes32 initialState, address[] memory initialPermissions) public returns (address) {
        require(accounts[user].owner == address(0), "Account already exists");
        
        Account storage newAccount = accounts[user];
        newAccount.owner = user;
        newAccount.state = initialState;
        
        for (uint256 i = 0; i < initialPermissions.length; i++) {
            newAccount.permissions[initialPermissions[i]] = true;
        }
        
        emit AccountCreated(user, initialState);
        return user;
    }

    function setPermission(address user, address permission, bool status) public {
        require(accounts[user].owner == msg.sender, "Only the owner can set permissions");
        
        accounts[user].permissions[permission] = status;
        
        emit PermissionSet(user, permission, status);
    }

    function hasPermission(address user, address permission) public view returns (bool) {
        return accounts[user].permissions[permission];
    }

    function getState(address user) public view returns (bytes32) {
        return accounts[user].state;
    }

    function updateState(address user, bytes32 newState) public {
        require(accounts[user].owner == msg.sender, "Only the owner can update state");
        
        accounts[user].state = newState;
    }
}