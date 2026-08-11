// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.5.0) (utils/ReentrancyGuardTransient.sol)

abstract contract ReentrancyGuardTransient {
    bytes32 private constant REENTRANCY_GUARD_STORAGE =
        0x9b779b17422d0df92223018b32b4d1fa46e071723d6817e2486d003becc55f00;

    bool private reentrancyLock;

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
        reentrancyLock = true;
    }

    function _nonReentrantAfter() private {
        reentrancyLock = false;
    }

    function _reentrancyGuardEntered() internal view returns (bool) {
        return reentrancyLock;
    }

    function _reentrancyGuardStorageSlot() internal pure virtual returns (bytes32) {
        return REENTRANCY_GUARD_STORAGE;
    }
}