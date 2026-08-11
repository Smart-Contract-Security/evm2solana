// SPDX-License-Identifier: BUSL-1.1

import 'solana';

/// @title Timelocked
/// @notice Generic signal/execute/burn pattern with per-action delays. Default 7-day delay and
///         7-day expiry window. Inheritors implement `_authAdmin` and may override `_actionDelay`.
abstract contract Timelocked {
    uint64 public constant TIMELOCK_DELAY = 7 days;
    uint64 public constant TIMELOCK_EXPIRY = 7 days;

    struct PendingChange {
        bytes32 dataHash;
        uint64 signalTime;
        uint64 delay;
    }

    mapping(bytes32 => PendingChange) public pendingChanges;
    mapping(bytes32 => PendingChange) public pendingBurns;
    mapping(bytes32 => bool) public burnedActions;

    event ChangeSignaled(bytes32 action, bytes32 dataHash, uint64 executeTime, uint64 expiresAt);
    event ChangeExecuted(bytes32 action);
    event ChangeCanceled(bytes32 action);
    event ActionBurnSignaled(bytes32 action, uint64 executeTime, uint64 expiresAt);
    event ActionBurnExecuted(bytes32 action);
    event ActionBurnCanceled(bytes32 action);

    function _signal(
        bytes32 action,
        bytes32 dataHash
    ) internal {
        _signal(action, dataHash, TIMELOCK_DELAY);
    }

    /// @dev `delay` is committed at signal time and read back on execute. Overwrites any pending change.
    function _signal(
        bytes32 action,
        bytes32 dataHash,
        uint64 delay
    ) internal {
        if (burnedActions[action]) {
            revert();
        }
        pendingChanges[action] = PendingChange({dataHash: dataHash, signalTime: uint64(block.timestamp), delay: delay});
        emit ChangeSignaled(action, dataHash, uint64(block.timestamp) + delay, uint64(block.timestamp) + delay + TIMELOCK_EXPIRY);
    }

    function _execute(
        bytes32 action,
        bytes32 dataHash
    ) internal {
        if (burnedActions[action]) {
            revert();
        }
        _validateWindow(pendingChanges[action], dataHash);
        delete pendingChanges[action];
        emit ChangeExecuted(action);
    }

    function _cancel(
        bytes32 action
    ) internal {
        delete pendingChanges[action];
        emit ChangeCanceled(action);
    }

    /// @dev Burn storage is isolated from pendingChanges so a pending change can coexist with a
    ///      pending burn until the burn lands.
    function _signalBurn(
        bytes32 action,
        uint64 delay
    ) internal {
        if (burnedActions[action]) {
            revert();
        }
        pendingBurns[action] =
            PendingChange({dataHash: keccak256(abi.encode(action)), signalTime: uint64(block.timestamp), delay: delay});
        emit ActionBurnSignaled(action, uint64(block.timestamp) + delay, uint64(block.timestamp) + delay + TIMELOCK_EXPIRY);
    }

    /// @dev Irreversible. Clears any in-flight change for the action so it cannot land post-burn.
    function _executeBurn(
        bytes32 action
    ) internal {
        if (burnedActions[action]) {
            revert();
        }
        _validateWindow(pendingBurns[action], keccak256(abi.encode(action)));
        delete pendingBurns[action];
        burnedActions[action] = true;

        if (pendingChanges[action].signalTime > 0) {
            delete pendingChanges[action];
        }

        emit ActionBurnExecuted(action);
    }

    function _cancelBurn(
        bytes32 action
    ) internal {
        delete pendingBurns[action];
        emit ActionBurnCanceled(action);
    }

    function signalAction(
        bytes32 action,
        bytes32 dataHash
    ) external {
        _authAdmin(action);
        _signal(action, dataHash, _actionDelay(action));
    }

    function cancelAction(
        bytes32 action
    ) external {
        _authAdmin(action);
        _cancel(action);
    }

    function signalBurnAction(
        bytes32 action
    ) external {
        _authAdmin(action);
        _signalBurn(action, _burnDelay(action));
    }

    /// @notice Permissionless after the burn delay; the auth gate is at signal time.
    function executeBurnAction(
        bytes32 action
    ) external {
        _executeBurn(action);
    }

    function cancelBurnAction(
        bytes32 action
    ) external {
        _authAdmin(action);
        _cancelBurn(action);
    }

    function _validateWindow(
        PendingChange memory pending,
        bytes32 expectedHash
    ) internal view {
        if (pending.signalTime == 0) {
            revert();
        }
        if (pending.dataHash != expectedHash) {
            revert();
        }
        uint64 executeTime = pending.signalTime + pending.delay;
        if (uint64(block.timestamp) < executeTime) {
            revert();
        }
        if (uint64(block.timestamp) > executeTime + TIMELOCK_EXPIRY) {
            revert();
        }
    }

    function _pendingInfo(
        PendingChange memory pending
    ) internal pure returns (bool isPending, uint64 executeTime, uint64 expiresAt) {
        isPending = pending.signalTime > 0;
        if (isPending) {
            executeTime = pending.signalTime + pending.delay;
            expiresAt = executeTime + TIMELOCK_EXPIRY;
        }
    }

    /// @dev Authorization gate for signal/cancel/burn. Inheritors implement (e.g. `onlyOwner`).
    function _authAdmin(
        bytes32 action
    ) internal virtual;

    function _actionDelay(
        bytes32
    ) internal view virtual returns (uint64) {
        return TIMELOCK_DELAY;
    }

    function _burnDelay(
        bytes32 action
    ) internal view virtual returns (uint64) {
        return _actionDelay(action);
    }

    function isActionBurned(
        bytes32 action
    ) external view returns (bool) {
        return burnedActions[action];
    }

    function getPendingChange(
        bytes32 action
    ) external view returns (bool isPending, uint64 executeTime, uint64 expiresAt) {
        return _pendingInfo(pendingChanges[action]);
    }

    function getPendingBurn(
        bytes32 action
    ) external view returns (bool isPending, uint64 executeTime, uint64 expiresAt) {
        return _pendingInfo(pendingBurns[action]);
    }
}