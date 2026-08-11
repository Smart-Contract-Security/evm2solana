// SPDX-License-Identifier: GPL-3.0
// OneBalance Permission Manager Contract
// Part of the OneBalance Framework for managing permissions over user accounts
pragma solidity ^0.8.0;

contract PermissionManager {

    struct Permission {
        address owner;
        mapping(address => bool) permissions;
    }
    
    mapping(address => Permission) private accountPermissions;
    
    event PermissionGranted(address indexed owner, address indexed grantee);
    event PermissionRevoked(address indexed owner, address indexed grantee);

    function grantPermission(address grantee) public {
        Permission storage permission = accountPermissions[msg.sender];
        permission.owner = msg.sender;
        permission.permissions[grantee] = true;

        emit PermissionGranted(msg.sender, grantee);
    }

    function revokePermission(address grantee) public {
        Permission storage permission = accountPermissions[msg.sender];
        require(permission.permissions[grantee], "Permission not granted");

        permission.permissions[grantee] = false;

        emit PermissionRevoked(msg.sender, grantee);
    }

    function hasPermission(address owner, address grantee) public view returns (bool) {
        Permission storage permission = accountPermissions[owner];
        return permission.permissions[grantee];
    }
}