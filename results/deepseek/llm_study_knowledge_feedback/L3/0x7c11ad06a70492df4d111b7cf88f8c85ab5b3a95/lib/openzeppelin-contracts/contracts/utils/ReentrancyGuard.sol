// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.5.0) (utils/ReentrancyGuard.sol)

import {StorageSlot} from "./StorageSlot.sol";

abstract contract ReentrancyGuard {
    using StorageSlot for bytes32;

    bytes32 private constant REENTRANCY_GUARD_STORAGE =
        0x9b779b17422d0df92223018b32b4d1fa46e071723d6817e2486d003becc55f00;

    uint64 private constant NOT_ENTERED = 1;
    uint64 private constant ENTERED = 2;

    constructor() {
        StorageSlot.getUint64Slot(REENTRANCY_GUARD_STORAGE).value = NOT_ENTERED;
    }

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
            revert();
        }
    }

    function _nonReentrantBefore() private {
        _nonReentrantBeforeView();

        StorageSlot.getUint64Slot(REENTRANCY_GUARD_STORAGE).value = ENTERED;
    }

    function _nonReentrantAfter() private {
        StorageSlot.getUint64Slot(REENTRANCY_GUARD_STORAGE).value = NOT_ENTERED;
    }

    function _reentrancyGuardEntered() internal view returns (bool) {
        return StorageSlot.getUint64Slot(REENTRANCY_GUARD_STORAGE).value == ENTERED;
    }

    function _reentrancyGuardStorageSlot() internal pure virtual returns (bytes32) {
        return REENTRANCY_GUARD_STORAGE;
    }
}