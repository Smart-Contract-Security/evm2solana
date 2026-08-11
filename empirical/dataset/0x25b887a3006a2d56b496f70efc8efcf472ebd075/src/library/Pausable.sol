// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/// @dev Pause functions using a uint256 number
///      If the lowest bit is flipped, then all functions with `whenNotPaused` are paused
///      Other bits are used to pause each function with corresponding id as the bit index
abstract contract Pausable {
    error Paused(uint256 funcId);
    error NotPaused(uint256 funcId);

    event Pause(uint256 funcId);
    event Unpause(uint256 funcId);

    /// @dev Function only could be called when contract not paused
    modifier whenNotPaused(uint256 funcId) {
        _requireNotPaused(funcId);
        _;
    }

    /// @dev Function only could be called when contract paused
    modifier whenPaused(uint256 funcId) {
        _requirePaused(funcId);
        _;
    }

    /// @dev Only pauser can pause contract
    modifier onlyPauser() {
        _requirePauser();

        _;
    }

    function isPaused(uint256 funcId) public view virtual returns (bool) {
        uint256 funcIds = _funcIds();
        return funcIds == 1 || (funcIds & (1 << funcId)) != 0;
    }

    function pause(
        uint256 funcId
    ) external virtual onlyPauser returns (uint256) {
        uint256 funcIds = _funcIds() | (1 << funcId);

        _setFuncIds(funcIds);

        emit Pause(funcId);

        return funcIds;
    }

    function unpause(
        uint256 funcId
    ) external virtual onlyPauser returns (uint256) {
        uint256 funcIds = _funcIds() & (~(1 << funcId));

        _setFuncIds(funcIds);

        emit Unpause(funcId);

        return funcIds;
    }

    // @dev Revert if the contract is paused.
    function _requireNotPaused(uint256 funcId) internal view virtual {
        if (isPaused(funcId)) revert Paused(funcId);
    }

    /// @dev Revert if the contract is not paused.
    function _requirePaused(uint256 funcId) internal view virtual {
        if (!isPaused(funcId)) revert NotPaused(funcId);
    }

    /// @dev Revert if the sender is not owner.
    function _requirePauser() internal view {
        if (msg.sender != _pauser()) revert();
    }

    /// @dev who can pause contract
    function _pauser() internal view virtual returns (address);

    function _funcIds() internal view virtual returns (uint256);

    /// @dev update functions' status
    function _setFuncIds(uint256 funcIds) internal virtual;
}
