// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library TransientSlot {
    function asBoolean(bytes32 slot) internal pure returns (bytes32) {
        return slot;
    }

    function tload(bytes32 slot) internal view returns (bool) {
        // On Solana, transient storage is not available.
        // We use a regular account storage slot as a fallback.
        // This is not a true transient storage, but it works for reentrancy guard.
        // The slot is cleared after the transaction ends by the modifier.
        // However, on Solana, storage persists across transactions.
        // We use a regular storage variable instead.
        // This is a workaround.
        // Actually, we cannot use tload/tstore on Solana.
        // We will use a regular storage variable.
        // Fallback: use a regular storage variable
        // This will be implemented in the contract
        return false;
    }

    function tstore(bytes32 slot, bool value) internal {
        // Same as above, no transient storage on Solana
    }
}

abstract contract ReentrancyGuardTransient {
    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ReentrancyGuard")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant REENTRANCY_GUARD_STORAGE =
        0x9b779b17422d0df92223018b32b4d1fa46e071723d6817e2486d003becc55f00;

    // Since Solana does not support transient storage (EIP-1153),
    // we use a regular storage variable to track reentrancy.
    // This is not ideal for gas, but it works for Solang on Solana.
    bool private _reentrancyGuardEnteredFlag;

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
        if (_reentrancyGuardEnteredFlag) {
            revert("ReentrancyGuard: reentrant call");
        }
    }

    function _nonReentrantBefore() private {
        _nonReentrantBeforeView();
        _reentrancyGuardEnteredFlag = true;
    }

    function _nonReentrantAfter() private {
        _reentrancyGuardEnteredFlag = false;
    }

    function _reentrancyGuardEntered() internal view returns (bool) {
        return _reentrancyGuardEnteredFlag;
    }

    function _reentrancyGuardStorageSlot() internal pure virtual returns (bytes32) {
        return REENTRANCY_GUARD_STORAGE;
    }
}