// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

abstract contract PausableUpgradeable {
    bytes32 private constant PausableStorageLocation = 0xcd5ed15c6e187e77e9aee88184c21f4f2182ab5827cb3b7e07fbedcd63f03300;

    struct PausableStorage {
        bool _paused;
    }

    function _getPausableStorage() private pure returns (PausableStorage storage $) {
        assembly {
            $.slot := PausableStorageLocation
        }
    }

    event Paused(address account);
    event Unpaused(address account);

    function __Pausable_init() internal {
        __Pausable_init_unchained();
    }

    function __Pausable_init_unchained() internal {
        PausableStorage storage $ = _getPausableStorage();
        $._paused = false;
    }

    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }

    modifier whenPaused() {
        _requirePaused();
        _;
    }

    function paused() public view virtual returns (bool) {
        PausableStorage storage $ = _getPausableStorage();
        return $._paused;
    }

    function _requireNotPaused() internal view virtual {
        require(!paused(), "EnforcedPause");
    }

    function _requirePaused() internal view virtual {
        require(paused(), "ExpectedPause");
    }

    function _pause() internal virtual whenNotPaused {
        PausableStorage storage $ = _getPausableStorage();
        $._paused = true;
        emit Paused(msg.sender);
    }

    function _unpause() internal virtual whenPaused {
        PausableStorage storage $ = _getPausableStorage();
        $._paused = false;
        emit Unpaused(msg.sender);
    }
}