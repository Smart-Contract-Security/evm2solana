// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Solang on Solana does not support imports from external files in the same way.
// We inline a minimal AccessControl implementation and SafeCast utility.
// Also, Solana does not have msg.sender; we use tx.origin as a substitute.
// require with two arguments is not supported; we use require(condition) and revert on failure.

bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;

interface IAccessControlDefaultAdminRules {
    event DefaultAdminTransferScheduled(address indexed newAdmin, uint48 acceptSchedule);
    event DefaultAdminTransferCanceled();
    event DefaultAdminDelayChangeScheduled(uint48 newDelay, uint48 effectSchedule);
    event DefaultAdminDelayChangeCanceled();

    function defaultAdmin() external view returns (address);
    function pendingDefaultAdmin() external view returns (address newAdmin, uint48 schedule);
    function defaultAdminDelay() external view returns (uint48);
    function pendingDefaultAdminDelay() external view returns (uint48 newDelay, uint48 schedule);
    function defaultAdminDelayIncreaseWait() external view returns (uint48);
    function beginDefaultAdminTransfer(address newAdmin) external;
    function cancelDefaultAdminTransfer() external;
    function acceptDefaultAdminTransfer() external;
    function changeDefaultAdminDelay(uint48 newDelay) external;
    function rollbackDefaultAdminDelay() external;
}

interface IERC5313 {
    function owner() external view returns (address);
}

// Minimal AccessControl implementation for Solana/Solang
contract AccessControl {
    mapping(bytes32 => mapping(address => bool)) private _roles;

    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    function hasRole(bytes32 role, address account) public view returns (bool) {
        return _roles[role][account];
    }

    function _grantRole(bytes32 role, address account) internal virtual {
        if (!hasRole(role, account)) {
            _roles[role][account] = true;
            emit RoleGranted(role, account, msg.sender);
        }
    }

    function _revokeRole(bytes32 role, address account) internal virtual {
        if (hasRole(role, account)) {
            _roles[role][account] = false;
            emit RoleRevoked(role, account, msg.sender);
        }
    }

    function grantRole(bytes32 role, address account) public virtual {
        _grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) public virtual {
        _revokeRole(role, account);
    }

    function renounceRole(bytes32 role, address account) public virtual {
        require(account == msg.sender);
        _revokeRole(role, account);
    }

    function _setRoleAdmin(bytes32 role, bytes32 adminRole) internal virtual {
        // Minimal implementation: no admin role hierarchy
    }

    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return false;
    }
}

// Minimal SafeCast for uint48
library SafeCast {
    function toUint48(uint256 value) internal pure returns (uint48) {
        require(value <= type(uint48).max);
        return uint48(value);
    }
}

abstract contract AccessControlDefaultAdminRules is IAccessControlDefaultAdminRules, IERC5313, AccessControl {
    address private _pendingDefaultAdmin;
    uint48 private _pendingDefaultAdminSchedule;

    uint48 private _currentDelay;
    address private _currentDefaultAdmin;

    uint48 private _pendingDelay;
    uint48 private _pendingDelaySchedule;

    constructor(uint48 initialDelay, address initialDefaultAdmin) {
        require(initialDefaultAdmin != address(0));
        _currentDelay = initialDelay;
        _grantRole(DEFAULT_ADMIN_ROLE, initialDefaultAdmin);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        // type(IAccessControlDefaultAdminRules).interfaceId is bytes4, but Solang may compute it as bytes8.
        // We cast to bytes4 explicitly.
        bytes4 ifaceId = bytes4(keccak256("IAccessControlDefaultAdminRules"));
        return interfaceId == ifaceId || super.supportsInterface(interfaceId);
    }

    function owner() public view virtual returns (address) {
        return defaultAdmin();
    }

    function grantRole(bytes32 role, address account) public virtual override {
        require(role != DEFAULT_ADMIN_ROLE);
        super.grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) public virtual override {
        require(role != DEFAULT_ADMIN_ROLE);
        super.revokeRole(role, account);
    }

    function renounceRole(bytes32 role, address account) public virtual override {
        if (role == DEFAULT_ADMIN_ROLE && account == defaultAdmin()) {
            (address newDefaultAdmin, uint48 schedule) = pendingDefaultAdmin();
            require(
                newDefaultAdmin == address(0) && _isScheduleSet(schedule) && _hasSchedulePassed(schedule)
            );
            delete _pendingDefaultAdminSchedule;
        }
        super.renounceRole(role, account);
    }

    function _grantRole(bytes32 role, address account) internal virtual override {
        if (role == DEFAULT_ADMIN_ROLE) {
            require(defaultAdmin() == address(0));
            _currentDefaultAdmin = account;
        }
        super._grantRole(role, account);
    }

    function _revokeRole(bytes32 role, address account) internal virtual override {
        if (role == DEFAULT_ADMIN_ROLE && account == defaultAdmin()) {
            delete _currentDefaultAdmin;
        }
        super._revokeRole(role, account);
    }

    function _setRoleAdmin(bytes32 role, bytes32 adminRole) internal virtual override {
        require(role != DEFAULT_ADMIN_ROLE);
        super._setRoleAdmin(role, adminRole);
    }

    function defaultAdmin() public view virtual returns (address) {
        return _currentDefaultAdmin;
    }

    function pendingDefaultAdmin() public view virtual returns (address newAdmin, uint48 schedule) {
        return (_pendingDefaultAdmin, _pendingDefaultAdminSchedule);
    }

    function defaultAdminDelay() public view virtual returns (uint48) {
        uint48 schedule = _pendingDelaySchedule;
        return (_isScheduleSet(schedule) && _hasSchedulePassed(schedule)) ? _pendingDelay : _currentDelay;
    }

    function pendingDefaultAdminDelay() public view virtual returns (uint48 newDelay, uint48 schedule) {
        schedule = _pendingDelaySchedule;
        return (_isScheduleSet(schedule) && !_hasSchedulePassed(schedule)) ? (_pendingDelay, schedule) : (0, 0);
    }

    function defaultAdminDelayIncreaseWait() public view virtual returns (uint48) {
        return 5 days;
    }

    modifier onlyRole(bytes32 role) {
        require(hasRole(role, msg.sender));
        _;
    }

    function beginDefaultAdminTransfer(address newAdmin) public virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        _beginDefaultAdminTransfer(newAdmin);
    }

    function _beginDefaultAdminTransfer(address newAdmin) internal virtual {
        uint48 newSchedule = SafeCast.toUint48(block.timestamp) + defaultAdminDelay();
        _setPendingDefaultAdmin(newAdmin, newSchedule);
        emit DefaultAdminTransferScheduled(newAdmin, newSchedule);
    }

    function cancelDefaultAdminTransfer() public virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        _cancelDefaultAdminTransfer();
    }

    function _cancelDefaultAdminTransfer() internal virtual {
        _setPendingDefaultAdmin(address(0), 0);
    }

    function acceptDefaultAdminTransfer() public virtual {
        (address newDefaultAdmin, ) = pendingDefaultAdmin();
        require(msg.sender == newDefaultAdmin);
        _acceptDefaultAdminTransfer();
    }

    function _acceptDefaultAdminTransfer() internal virtual {
        (address newAdmin, uint48 schedule) = pendingDefaultAdmin();
        require(_isScheduleSet(schedule) && _hasSchedulePassed(schedule));
        _revokeRole(DEFAULT_ADMIN_ROLE, defaultAdmin());
        _grantRole(DEFAULT_ADMIN_ROLE, newAdmin);
        delete _pendingDefaultAdmin;
        delete _pendingDefaultAdminSchedule;
    }

    function changeDefaultAdminDelay(uint48 newDelay) public virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        _changeDefaultAdminDelay(newDelay);
    }

    function _changeDefaultAdminDelay(uint48 newDelay) internal virtual {
        uint48 newSchedule = SafeCast.toUint48(block.timestamp) + _delayChangeWait(newDelay);
        _setPendingDelay(newDelay, newSchedule);
        emit DefaultAdminDelayChangeScheduled(newDelay, newSchedule);
    }

    function rollbackDefaultAdminDelay() public virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        _rollbackDefaultAdminDelay();
    }

    function _rollbackDefaultAdminDelay() internal virtual {
        _setPendingDelay(0, 0);
    }

    function _delayChangeWait(uint48 newDelay) internal view virtual returns (uint48) {
        uint48 currentDelay = defaultAdminDelay();

        if (newDelay > currentDelay) {
            uint48 maxWait = defaultAdminDelayIncreaseWait();
            if (newDelay < maxWait) {
                return newDelay;
            } else {
                return maxWait;
            }
        } else {
            return currentDelay - newDelay;
        }
    }

    function _setPendingDefaultAdmin(address newAdmin, uint48 newSchedule) private {
        (, uint48 oldSchedule) = pendingDefaultAdmin();

        _pendingDefaultAdmin = newAdmin;
        _pendingDefaultAdminSchedule = newSchedule;

        if (_isScheduleSet(oldSchedule)) {
            emit DefaultAdminTransferCanceled();
        }
    }

    function _setPendingDelay(uint48 newDelay, uint48 newSchedule) private {
        uint48 oldSchedule = _pendingDelaySchedule;

        if (_isScheduleSet(oldSchedule)) {
            if (_hasSchedulePassed(oldSchedule)) {
                _currentDelay = _pendingDelay;
            } else {
                emit DefaultAdminDelayChangeCanceled();
            }
        }

        _pendingDelay = newDelay;
        _pendingDelaySchedule = newSchedule;
    }

    function _isScheduleSet(uint48 schedule) private pure returns (bool) {
        return schedule != 0;
    }

    function _hasSchedulePassed(uint48 schedule) private view returns (bool) {
        return schedule < block.timestamp;
    }
}