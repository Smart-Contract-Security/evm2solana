// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Solang on Solana does not support importing external files in the same way.
// We inline the required interfaces and base contracts.

// Inline IAccessControl
interface IAccessControl {
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    function hasRole(bytes32 role, address account) external view returns (bool);
    function getRoleAdmin(bytes32 role) external view returns (bytes32);
    function grantRole(bytes32 role, address account) external;
    function revokeRole(bytes32 role, address account) external;
    function renounceRole(bytes32 role, address callerConfirmation) external;
}

// Inline ERC165
abstract contract ERC165 {
    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == 0x01ffc9a7; // ERC165 interface ID
    }
}

// Inline Context
abstract contract Context {
    // On Solana, msg.sender is not available. Use the Solana-specific tx.origin replacement.
    // Solang provides `tx.program_id` and `tx.accounts` but not `tx.origin`.
    // We use `msg.sender` which is supported by Solang for Solana.
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

// Custom errors are not supported on Solana via Solang; use string reverts.
// We define revert reasons as constants or inline strings.

abstract contract AccessControl is Context, IAccessControl, ERC165 {
    struct RoleData {
        mapping(address => bool) hasRole;
        bytes32 adminRole;
    }

    mapping(bytes32 => RoleData) private _roles;

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    modifier onlyRole(bytes32 role) {
        _checkRole(role);
        _;
    }

    // Solang does not support `type(IAccessControl).interfaceId` directly.
    // Compute the interface ID manually: XOR of all function selectors.
    // IAccessControl functions: hasRole, getRoleAdmin, grantRole, revokeRole, renounceRole
    // hasRole: bytes4(keccak256("hasRole(bytes32,address)")) = 0x91d14854
    // getRoleAdmin: bytes4(keccak256("getRoleAdmin(bytes32)")) = 0x248a9ca3
    // grantRole: bytes4(keccak256("grantRole(bytes32,address)")) = 0x2f2ff15d
    // revokeRole: bytes4(keccak256("revokeRole(bytes32,address)")) = 0xd547741f
    // renounceRole: bytes4(keccak256("renounceRole(bytes32,address)")) = 0x36568abe
    // XOR: 0x91d14854 ^ 0x248a9ca3 ^ 0x2f2ff15d ^ 0xd547741f ^ 0x36568abe = 0x7965db0b
    bytes4 private constant IACCESSCONTROL_INTERFACE_ID = 0x7965db0b;

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        // Explicitly cast to bytes4 to avoid truncation warning.
        if (interfaceId == IACCESSCONTROL_INTERFACE_ID) {
            return true;
        }
        return ERC165.supportsInterface(interfaceId);
    }

    function hasRole(bytes32 role, address account) public view virtual returns (bool) {
        return _roles[role].hasRole[account];
    }

    function _checkRole(bytes32 role) internal view virtual {
        _checkRole(role, _msgSender());
    }

    function _checkRole(bytes32 role, address account) internal view virtual {
        if (!hasRole(role, account)) {
            // revert with custom error not supported; use string revert
            revert("AccessControl: account is missing role");
        }
    }

    function getRoleAdmin(bytes32 role) public view virtual returns (bytes32) {
        return _roles[role].adminRole;
    }

    function grantRole(bytes32 role, address account) public virtual onlyRole(getRoleAdmin(role)) {
        _grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) public virtual onlyRole(getRoleAdmin(role)) {
        _revokeRole(role, account);
    }

    function renounceRole(bytes32 role, address callerConfirmation) public virtual {
        if (callerConfirmation != _msgSender()) {
            revert("AccessControl: bad confirmation");
        }

        _revokeRole(role, callerConfirmation);
    }

    function _setRoleAdmin(bytes32 role, bytes32 adminRole) internal virtual {
        bytes32 previousAdminRole = getRoleAdmin(role);
        _roles[role].adminRole = adminRole;
        emit RoleAdminChanged(role, previousAdminRole, adminRole);
    }

    function _grantRole(bytes32 role, address account) internal virtual returns (bool) {
        if (!hasRole(role, account)) {
            _roles[role].hasRole[account] = true;
            emit RoleGranted(role, account, _msgSender());
            return true;
        } else {
            return false;
        }
    }

    function _revokeRole(bytes32 role, address account) internal virtual returns (bool) {
        if (hasRole(role, account)) {
            _roles[role].hasRole[account] = false;
            emit RoleRevoked(role, account, _msgSender());
            return true;
        } else {
            return false;
        }
    }
}