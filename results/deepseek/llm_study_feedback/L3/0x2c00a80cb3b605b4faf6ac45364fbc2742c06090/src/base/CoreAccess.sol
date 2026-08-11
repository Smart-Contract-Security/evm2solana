// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Roles } from "../libraries/Roles.sol";

/// @title CoreAccess
abstract contract CoreAccess {
    address public authority;
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
        authority = authority_;
        emit AuthoritySet(authority_);
    }

    modifier onlyAdmin() {
        _checkRole(Roles.DEFAULT_ADMIN_ROLE, tx.accounts[0].key);
        _;
    }

    modifier onlySuperAdmin() {
        _checkRole(Roles.SUPER_ADMIN_ROLE, tx.accounts[0].key);
        _;
    }

    modifier onlyRole(bytes32 role) {
        _checkRole(role, tx.accounts[0].key);
        _;
    }

    function hasRole(bytes32 role, address account) public view returns (bool) {
        if (authority == address(0)) {
            return false;
        }
        AccountMeta[] memory metas = new AccountMeta[](1);
        metas[0] = AccountMeta({pubkey: authority, is_signer: false, is_writable: false});
        (bool success, bytes memory result) = authority.call{accounts: metas}(
            abi.encodeWithSignature("hasRole(bytes32,address)", role, account)
        );
        if (!success) {
            return false;
        }
        return abi.decode(result, (bool));
    }

    function _checkRole(bytes32 role, address account) internal view {
        require(hasRole(role, account), "CoreAccess: missing role");
    }
}