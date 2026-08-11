// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IVaultAuthority } from "../interfaces/IVaultAuthority.sol";
import { Roles } from "../libraries/Roles.sol";

/// @title VaultAuthority
/// @notice Shared authority for one vault deployment. Super admins only manage admins; admins manage vault roles.
contract VaultAuthority is IVaultAuthority {
    mapping(bytes32 => mapping(address => bool)) private _roles;
    bool private _initialized;

    modifier onlySuperAdmin() {
        _onlySuperAdmin();
        _;
    }

    modifier onlyAdmin() {
        _onlyAdmin();
        _;
    }

    constructor(address superAdmin, address admin, address extraAdmin) {
        if (superAdmin != address(0)) {
            _initialize(superAdmin, admin);
            if (extraAdmin != address(0) && extraAdmin != admin) {
                _grantRole(Roles.DEFAULT_ADMIN_ROLE, extraAdmin);
            }
        }
    }

    function initialize(address superAdmin, address admin) external {
        _initialize(superAdmin, admin);
    }

    function _initialize(address superAdmin, address admin) internal {
        require(!_initialized, "VaultAuthority: initialized");
        require(superAdmin != address(0) && admin != address(0), "VaultAuthority: zero address");
        _initialized = true;
        _grantRole(Roles.SUPER_ADMIN_ROLE, superAdmin);
        _grantRole(Roles.DEFAULT_ADMIN_ROLE, admin);
        if (msg.sender != superAdmin && msg.sender != admin) _grantRole(Roles.DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function hasRole(bytes32 role, address account) external view returns (bool) {
        return _roles[role][account];
    }

    function grantAdmin(address account) external onlySuperAdmin {
        require(account != address(0), "VaultAuthority: zero account");
        _grantRole(Roles.DEFAULT_ADMIN_ROLE, account);
    }

    function revokeAdmin(address account) external onlySuperAdmin {
        _revokeRole(Roles.DEFAULT_ADMIN_ROLE, account);
    }

    function grantRole(bytes32 role, address account) external {
        require(account != address(0), "VaultAuthority: zero account");
        if (role == Roles.DEFAULT_ADMIN_ROLE) {
            require(_roles[Roles.SUPER_ADMIN_ROLE][msg.sender], "VaultAuthority: not super admin");
        } else {
            require(_roles[Roles.DEFAULT_ADMIN_ROLE][msg.sender], "VaultAuthority: not admin");
            require(role != Roles.SUPER_ADMIN_ROLE, "VaultAuthority: super admin fixed");
        }
        _grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) external {
        if (role == Roles.DEFAULT_ADMIN_ROLE) {
            require(_roles[Roles.SUPER_ADMIN_ROLE][msg.sender], "VaultAuthority: not super admin");
        } else {
            require(_roles[Roles.DEFAULT_ADMIN_ROLE][msg.sender], "VaultAuthority: not admin");
            require(role != Roles.SUPER_ADMIN_ROLE, "VaultAuthority: super admin fixed");
        }
        _revokeRole(role, account);
    }

    function renounceRole(bytes32 role, address account) external {
        require(account == msg.sender, "VaultAuthority: can only renounce self");
        require(role != Roles.SUPER_ADMIN_ROLE, "VaultAuthority: super admin fixed");
        _revokeRole(role, account);
    }

    function _grantRole(bytes32 role, address account) internal {
        if (_roles[role][account]) return;
        _roles[role][account] = true;
        emit RoleGranted(role, account, msg.sender);
    }

    function _revokeRole(bytes32 role, address account) internal {
        if (!_roles[role][account]) return;
        _roles[role][account] = false;
        emit RoleRevoked(role, account, msg.sender);
    }

    function _onlySuperAdmin() internal view {
        require(_roles[Roles.SUPER_ADMIN_ROLE][msg.sender], "VaultAuthority: not super admin");
    }

    function _onlyAdmin() internal view {
        require(_roles[Roles.DEFAULT_ADMIN_ROLE][msg.sender], "VaultAuthority: not admin");
    }
}
