// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

abstract contract ReentrancyGuardTransient {
    bytes32 private constant REENTRANCY_GUARD_STORAGE =
        0x9b779b17422d0df92223018b32b4d1fa46e071723d6817e2486d003becc55f00;

    error ReentrancyGuardReentrantCall();

    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    modifier nonReentrantView() {
        _nonReentrantBeforeView();
        _;
    }

    function _nonReentrantBeforeView() private view {
        if (_reentrancyGuardEntered()) {
            revert("ReentrancyGuard: reentrant call");
        }
    }

    function _nonReentrantBefore() private {
        _nonReentrantBeforeView();
        _setReentrancyGuard(true);
    }

    function _nonReentrantAfter() private {
        _setReentrancyGuard(false);
    }

    function _reentrancyGuardEntered() internal view returns (bool) {
        return _getReentrancyGuard();
    }

    function _getReentrancyGuard() internal view returns (bool entered) {
        bytes32 slot = REENTRANCY_GUARD_STORAGE;
        bool value;
        assembly {
            value := sload(slot)
        }
        return value;
    }

    function _setReentrancyGuard(bool entered) internal {
        bytes32 slot = REENTRANCY_GUARD_STORAGE;
        assembly {
            sstore(slot, entered)
        }
    }
}