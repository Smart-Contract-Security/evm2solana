// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IVaultAuthority } from "../interfaces/IVaultAuthority.sol";
import { Roles } from "../libraries/Roles.sol";

/// @title CoreAccess
abstract contract CoreAccess {
    IVaultAuthority public authority;
    bool private _coreAccessInitialized;

    event AuthoritySet(address indexed authority);

    constructor(address authority_) {
        if (authority_ == address(0)) {
            _coreAccessInitialized = true;
        } else {
            _initializeCoreAccess(authority_);
        }
    }

    function _initializeCoreAccess(address authority_) internal {
        require(!_coreAccessInitialized, "CoreAccess: initialized");
        require(authority_ != address(0), "CoreAccess: zero authority");
        _coreAccessInitialized = true;
        authority = IVaultAuthority(authority_);
        emit AuthoritySet(authority_);
    }

    modifier onlyAdmin() {
        _checkRole(Roles.DEFAULT_ADMIN_ROLE, msg.sender);
        _;
    }

    modifier onlySuperAdmin() {
        _checkRole(Roles.SUPER_ADMIN_ROLE, msg.sender);
        _;
    }

    modifier onlyRole(bytes32 role) {
        _checkRole(role, msg.sender);
        _;
    }

    function hasRole(bytes32 role, address account) public view returns (bool) {
        return address(authority) != address(0) && authority.hasRole(role, account);
    }

    function _checkRole(bytes32 role, address account) internal view {
        require(hasRole(role, account), "CoreAccess: missing role");
    }
}