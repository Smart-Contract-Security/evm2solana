// SPDX-License-Identifier: MIT

import {AccountMeta} from 'solana';

/**
 * @dev Extension of {AccessControl} that allows specifying special rules to manage
 * the `DEFAULT_ADMIN_ROLE` holder, which is a sensitive role with special permissions
 * over other roles that may potentially have privileged rights in the system.
 *
 * If a specific role doesn't have an admin role assigned, the holder of the
 * `DEFAULT_ADMIN_ROLE` will have the ability to grant it and revoke it.
 *
 * This contract implements the following risk mitigations on top of {AccessControl}:
 *
 * * Only one account holds the `DEFAULT_ADMIN_ROLE` since deployment until it's potentially renounced.
 * * Enforces a 2-step process to transfer the `DEFAULT_ADMIN_ROLE` to another account.
 * * Enforces a configurable delay between the two steps, with the ability to cancel before the transfer is accepted.
 * * The delay can be changed by scheduling, see {changeDefaultAdminDelay}.
 * * It is not possible to use another role to manage the `DEFAULT_ADMIN_ROLE`.
 *
 * Example usage:
 *
 * ```solidity
 * contract MyToken is AccessControlDefaultAdminRules {
 *   constructor() AccessControlDefaultAdminRules(
 *     3 days,
 *     msg.sender // Explicit initial `DEFAULT_ADMIN_ROLE` holder
 *    ) {}
 * }
 * ```
 *
 * _Available since v4.9._
 */
abstract contract AccessControlDefaultAdminRules {
    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;

    // pending admin pair read/written together frequently
    address private _pendingDefaultAdmin;
    uint64 private _pendingDefaultAdminSchedule; // 0 == unset

    uint64 private _currentDelay;
    address private _currentDefaultAdmin;

    // pending delay pair read/written together frequently
    uint64 private _pendingDelay;
    uint64 private _pendingDelaySchedule; // 0 == unset

    event DefaultAdminTransferScheduled(address indexed newAdmin, uint64 indexed schedule);
    event DefaultAdminTransferCanceled();
    event DefaultAdminDelayChangeScheduled(uint64 indexed newDelay, uint64 indexed schedule);
    event DefaultAdminDelayChangeCanceled();

    /**
     * @dev Sets the initial values for {defaultAdminDelay} and {defaultAdmin} address.
     */
    constructor(uint64 initialDelay, address initialDefaultAdmin) {
        require(initialDefaultAdmin != address(0), "AccessControl: 0 default admin");
        _currentDelay = initialDelay;
        _grantRole(DEFAULT_ADMIN_ROLE, initialDefaultAdmin);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == 0x0e0b8b6e || _supportsInterface(interfaceId);
    }

    function _supportsInterface(bytes4 interfaceId) internal view virtual returns (bool) {
        return false;
    }

    /**
     * @dev See {IERC5313-owner}.
     */
    function owner() public view virtual returns (address) {
        return defaultAdmin();
    }

    ///
    /// Override AccessControl role management
    ///

    /**
     * @dev See {AccessControl-grantRole}. Reverts for `DEFAULT_ADMIN_ROLE`.
     */
    function grantRole(bytes32 role, address account) public virtual {
        require(role != DEFAULT_ADMIN_ROLE, "AccessControl: can't directly grant default admin role");
        _grantRole(role, account);
    }

    /**
     * @dev See {AccessControl-revokeRole}. Reverts for `DEFAULT_ADMIN_ROLE`.
     */
    function revokeRole(bytes32 role, address account) public virtual {
        require(role != DEFAULT_ADMIN_ROLE, "AccessControl: can't directly revoke default admin role");
        _revokeRole(role, account);
    }

    /**
     * @dev See {AccessControl-renounceRole}.
     *
     * For the `DEFAULT_ADMIN_ROLE`, it only allows renouncing in two steps by first calling
     * {beginDefaultAdminTransfer} to the `address(0)`, so it's required that the {pendingDefaultAdmin} schedule
     * has also passed when calling this function.
     *
     * After its execution, it will not be possible to call `onlyRole(DEFAULT_ADMIN_ROLE)` functions.
     *
     * NOTE: Renouncing `DEFAULT_ADMIN_ROLE` will leave the contract without a {defaultAdmin},
     * thereby disabling any functionality that is only available for it, and the possibility of reassigning a
     * non-administrated role.
     */
    function renounceRole(bytes32 role, address account) public virtual {
        if (role == DEFAULT_ADMIN_ROLE && account == defaultAdmin()) {
            (address newDefaultAdmin, uint64 schedule) = pendingDefaultAdmin();
            require(
                newDefaultAdmin == address(0) && _isScheduleSet(schedule) && _hasSchedulePassed(schedule),
                "AccessControl: only can renounce in two delayed steps"
            );
            delete _pendingDefaultAdminSchedule;
        }
        _renounceRole(role, account);
    }

    function _renounceRole(bytes32 role, address account) internal virtual {}

    /**
     * @dev See {AccessControl-_grantRole}.
     *
     * For `DEFAULT_ADMIN_ROLE`, it only allows granting if there isn't already a {defaultAdmin} or if the
     * role has been previously renounced.
     *
     * NOTE: Exposing this function through another mechanism may make the `DEFAULT_ADMIN_ROLE`
     * assignable again. Make sure to guarantee this is the expected behavior in your implementation.
     */
    function _grantRole(bytes32 role, address account) internal virtual {
        if (role == DEFAULT_ADMIN_ROLE) {
            require(defaultAdmin() == address(0), "AccessControl: default admin already granted");
            _currentDefaultAdmin = account;
        }
    }

    /**
     * @dev See {AccessControl-_revokeRole}.
     */
    function _revokeRole(bytes32 role, address account) internal virtual {
        if (role == DEFAULT_ADMIN_ROLE && account == defaultAdmin()) {
            delete _currentDefaultAdmin;
        }
    }

    /**
     * @dev See {AccessControl-_setRoleAdmin}. Reverts for `DEFAULT_ADMIN_ROLE`.
     */
    function _setRoleAdmin(bytes32 role, bytes32 adminRole) internal virtual {
        require(role != DEFAULT_ADMIN_ROLE, "AccessControl: can't violate default admin rules");
    }

    ///
    /// AccessControlDefaultAdminRules accessors
    ///

    function defaultAdmin() public view virtual returns (address) {
        return _currentDefaultAdmin;
    }

    function pendingDefaultAdmin() public view virtual returns (address newAdmin, uint64 schedule) {
        return (_pendingDefaultAdmin, _pendingDefaultAdminSchedule);
    }

    function defaultAdminDelay() public view virtual returns (uint64) {
        uint64 schedule = _pendingDelaySchedule;
        return (_isScheduleSet(schedule) && _hasSchedulePassed(schedule)) ? _pendingDelay : _currentDelay;
    }

    function pendingDefaultAdminDelay() public view virtual returns (uint64 newDelay, uint64 schedule) {
        schedule = _pendingDelaySchedule;
        return (_isScheduleSet(schedule) && !_hasSchedulePassed(schedule)) ? (_pendingDelay, schedule) : (0, 0);
    }

    function defaultAdminDelayIncreaseWait() public view virtual returns (uint64) {
        return 5 days;
    }

    ///
    /// AccessControlDefaultAdminRules public and internal setters for defaultAdmin/pendingDefaultAdmin
    ///

    function beginDefaultAdminTransfer(address newAdmin) public virtual {
        require(_currentDefaultAdmin == tx.accounts.dataAccount.key, "AccessControl: not default admin");
        _beginDefaultAdminTransfer(newAdmin);
    }

    /**
     * @dev See {beginDefaultAdminTransfer}.
     *
     * Internal function without access restriction.
     */
    function _beginDefaultAdminTransfer(address newAdmin) internal virtual {
        uint64 newSchedule = toUint64(uint64(block.timestamp)) + defaultAdminDelay();
        _setPendingDefaultAdmin(newAdmin, newSchedule);
        emit DefaultAdminTransferScheduled(newAdmin, newSchedule);
    }

    function cancelDefaultAdminTransfer() public virtual {
        require(_currentDefaultAdmin == tx.accounts.dataAccount.key, "AccessControl: not default admin");
        _cancelDefaultAdminTransfer();
    }

    /**
     * @dev See {cancelDefaultAdminTransfer}.
     *
     * Internal function without access restriction.
     */
    function _cancelDefaultAdminTransfer() internal virtual {
        _setPendingDefaultAdmin(address(0), 0);
    }

    function acceptDefaultAdminTransfer() public virtual {
        (address newDefaultAdmin, ) = pendingDefaultAdmin();
        require(tx.accounts.dataAccount.key == newDefaultAdmin, "AccessControl: pending admin must accept");
        _acceptDefaultAdminTransfer();
    }

    /**
     * @dev See {acceptDefaultAdminTransfer}.
     *
     * Internal function without access restriction.
     */
    function _acceptDefaultAdminTransfer() internal virtual {
        (address newAdmin, uint64 schedule) = pendingDefaultAdmin();
        require(_isScheduleSet(schedule) && _hasSchedulePassed(schedule), "AccessControl: transfer delay not passed");
        _revokeRole(DEFAULT_ADMIN_ROLE, defaultAdmin());
        _grantRole(DEFAULT_ADMIN_ROLE, newAdmin);
        delete _pendingDefaultAdmin;
        delete _pendingDefaultAdminSchedule;
    }

    ///
    /// AccessControlDefaultAdminRules public and internal setters for defaultAdminDelay/pendingDefaultAdminDelay
    ///

    function changeDefaultAdminDelay(uint64 newDelay) public virtual {
        require(_currentDefaultAdmin == tx.accounts.dataAccount.key, "AccessControl: not default admin");
        _changeDefaultAdminDelay(newDelay);
    }

    /**
     * @dev See {changeDefaultAdminDelay}.
     *
     * Internal function without access restriction.
     */
    function _changeDefaultAdminDelay(uint64 newDelay) internal virtual {
        uint64 newSchedule = toUint64(uint64(block.timestamp)) + _delayChangeWait(newDelay);
        _setPendingDelay(newDelay, newSchedule);
        emit DefaultAdminDelayChangeScheduled(newDelay, newSchedule);
    }

    function rollbackDefaultAdminDelay() public virtual {
        require(_currentDefaultAdmin == tx.accounts.dataAccount.key, "AccessControl: not default admin");
        _rollbackDefaultAdminDelay();
    }

    /**
     * @dev See {rollbackDefaultAdminDelay}.
     *
     * Internal function without access restriction.
     */
    function _rollbackDefaultAdminDelay() internal virtual {
        _setPendingDelay(0, 0);
    }

    /**
     * @dev Returns the amount of seconds to wait after the `newDelay` will
     * become the new {defaultAdminDelay}.
     *
     * The value returned guarantees that if the delay is reduced, it will go into effect
     * after a wait that honors the previously set delay.
     *
     * See {defaultAdminDelayIncreaseWait}.
     */
    function _delayChangeWait(uint64 newDelay) internal view virtual returns (uint64) {
        uint64 currentDelay = defaultAdminDelay();

        // When increasing the delay, we schedule the delay change to occur after a period of "new delay" has passed, up
        // to a maximum given by defaultAdminDelayIncreaseWait, by default 5 days. For example, if increasing from 1 day
        // to 3 days, the new delay will come into effect after 3 days. If increasing from 1 day to 10 days, the new
        // delay will come into effect after 5 days. The 5 day wait period is intended to be able to fix an error like
        // using milliseconds instead of seconds.
        //
        // When decreasing the delay, we wait the difference between "current delay" and "new delay". This guarantees
        // that an admin transfer cannot be made faster than "current delay" at the time the delay change is scheduled.
        // For example, if decreasing from 10 days to 3 days, the new delay will come into effect after 7 days.
        return
            newDelay > currentDelay
                ? minUint64(newDelay, defaultAdminDelayIncreaseWait())
                : currentDelay - newDelay;
    }

    ///
    /// Private setters
    ///

    /**
     * @dev Setter of the tuple for pending admin and its schedule.
     *
     * May emit a DefaultAdminTransferCanceled event.
     */
    function _setPendingDefaultAdmin(address newAdmin, uint64 newSchedule) private {
        (, uint64 oldSchedule) = pendingDefaultAdmin();

        _pendingDefaultAdmin = newAdmin;
        _pendingDefaultAdminSchedule = newSchedule;

        // An `oldSchedule` from `pendingDefaultAdmin()` is only set if it hasn't been accepted.
        if (_isScheduleSet(oldSchedule)) {
            // Emit for implicit cancellations when another default admin was scheduled.
            emit DefaultAdminTransferCanceled();
        }
    }

    /**
     * @dev Setter of the tuple for pending delay and its schedule.
     *
     * May emit a DefaultAdminDelayChangeCanceled event.
     */
    function _setPendingDelay(uint64 newDelay, uint64 newSchedule) private {
        uint64 oldSchedule = _pendingDelaySchedule;

        if (_isScheduleSet(oldSchedule)) {
            if (_hasSchedulePassed(oldSchedule)) {
                // Materialize a virtual delay
                _currentDelay = _pendingDelay;
            } else {
                // Emit for implicit cancellations when another delay was scheduled.
                emit DefaultAdminDelayChangeCanceled();
            }
        }

        _pendingDelay = newDelay;
        _pendingDelaySchedule = newSchedule;
    }

    ///
    /// Private helpers
    ///

    /**
     * @dev Defines if an `schedule` is considered set. For consistency purposes.
     */
    function _isScheduleSet(uint64 schedule) private pure returns (bool) {
        return schedule != 0;
    }

    /**
     * @dev Defines if an `schedule` is considered passed. For consistency purposes.
     */
    function _hasSchedulePassed(uint64 schedule) private view returns (bool) {
        return schedule < block.timestamp;
    }

    /**
     * @dev SafeCast toUint64 replacement.
     */
    function toUint64(uint64 value) private pure returns (uint64) {
        return value;
    }

    /**
     * @dev Math.min replacement for uint64.
     */
    function minUint64(uint64 a, uint64 b) private pure returns (uint64) {
        return a < b ? a : b;
    }
}