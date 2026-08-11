// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

abstract contract Context {
    function _msgSender() internal view returns (address) {
        return tx.origin;
    }

    function _msgData() internal view returns (bytes calldata) {
        return msg.data;
    }
}

abstract contract Pausable is Context {
    bool private _paused;

    event Paused(address account);
    event Unpaused(address account);

    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }

    modifier whenPaused() {
        _requirePaused();
        _;
    }

    function paused() public view returns (bool) {
        return _paused;
    }

    function _requireNotPaused() internal view {
        if (paused()) {
            revert("EnforcedPause");
        }
    }

    function _requirePaused() internal view {
        if (!paused()) {
            revert("ExpectedPause");
        }
    }

    function _pause() internal whenNotPaused {
        _paused = true;
        emit Paused(_msgSender());
    }

    function _unpause() internal whenPaused {
        _paused = false;
        emit Unpaused(_msgSender());
    }
}