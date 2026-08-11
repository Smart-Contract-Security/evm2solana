// SPDX-License-Identifier: MIT

import {AccountInfo} from 'solana';

library Roles {
    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 constant SUPER_ADMIN_ROLE = keccak256("SUPER_ADMIN_ROLE");
}

interface IVaultAuthority {
    function hasRole(bytes32 role, address account) external view returns (bool);
}

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
        _checkRole(Roles.DEFAULT_ADMIN_ROLE, tx.accounts.dataAccount.key);
        _;
    }

    modifier onlySuperAdmin() {
        _checkRole(Roles.SUPER_ADMIN_ROLE, tx.accounts.dataAccount.key);
        _;
    }

    modifier onlyRole(bytes32 role) {
        _checkRole(role, tx.accounts.dataAccount.key);
        _;
    }

    function _authorizeUpgrade(address) internal onlySuperAdmin { }

    function hasRole(bytes32 role, address account) public view returns (bool) {
        if (authority == address(0)) {
            return false;
        }
        (bool success, bytes memory result) = authority.call{accounts: []}(abi.encodeWithSignature("hasRole(bytes32,address)", role, account));
        require(success, "CoreAccess: call failed");
        return abi.decode(result, (bool));
    }

    function _checkRole(bytes32 role, address account) internal view {
        require(hasRole(role, account), "CoreAccess: missing role");
    }
}