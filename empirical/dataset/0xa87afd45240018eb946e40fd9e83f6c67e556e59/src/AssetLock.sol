// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {SingleAdminAccessControl} from "src/utils/SingleAdminAccessControl.sol";

struct UserLock {
    uint128 amount;
    uint64 lockStartTime;
    uint64 lockEndTime;
}

struct AssetInfo {
    bool isSupported;
    uint128 maxLockCapacity;
    uint96 minLockAmount;
}

struct LockDuration {
    uint128 minDuration;
    uint128 maxDuration;
}

/// @title AssetLock
/// @notice AssetLock is a contract that allows users to lock their assets for a certain duration
contract AssetLock is SingleAdminAccessControl, Pausable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                             ERRORS
    //////////////////////////////////////////////////////////////*/

    error UnsupportedAsset();
    error InvalidLockDuration();
    error MaxLockCapacityExceeded();
    error LockNotEnded();
    error NoActiveLock();
    error ZeroInput();
    error BelowMinimumLock();
    error InvalidLockIndex();

    /*//////////////////////////////////////////////////////////////
                             EVENTS
    //////////////////////////////////////////////////////////////*/

    event AssetInfoSet(address indexed asset, bool isSupported, uint256 maxLockCapacity, uint256 minLockAmount);
    event LockDurationSet(uint128 minDuration, uint128 maxDuration);
    event AssetLocked(address indexed user, address indexed asset, uint256 amount, uint128 unlockTime);
    event AssetUnlocked(address indexed user, address indexed asset, uint256 amount, uint256 lockIndex);
    event EnforceLockSet(bool enforceLock);

    /*//////////////////////////////////////////////////////////////
                             STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The role for the manager
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @notice The role that is allowed to pause and unpause the contract
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice The range of lock duration
    LockDuration public lockDuration;

    /// @notice The mapping of user locks
    mapping(address user => mapping(address asset => UserLock[] locks)) private userLocks;

    /// @notice The mapping of asset info
    mapping(address asset => AssetInfo assetInfo) private assetInfo;

    /// @notice The mapping of total locked assets
    mapping(address asset => uint256 totalLocked) public totalLocked;

    /// @notice Whether to enforce locking, if false, users can withdraw their assets at any time
    bool public enforceLock;

    /*//////////////////////////////////////////////////////////////
                             INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    constructor(address _admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _setEnforceLock(true);
        _setLockDuration(90 days, 365 days);
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Set whether to enforce locking
    /// @param _enforceLock Whether to enforce locking
    function setEnforceLock(bool _enforceLock) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setEnforceLock(_enforceLock);
    }

    /// @notice Pauses the contract
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Unpauses the contract
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                        MANAGER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Set the info of an asset
    /// @param _asset The asset address
    /// @param _isSupported Whether the asset is supported
    /// @param _maxLockCapacity The maximum lock capacity of the asset
    /// @param _minLockAmount The minimum lock amount of the asset
    function setAssetInfo(address _asset, bool _isSupported, uint128 _maxLockCapacity, uint96 _minLockAmount)
        external
        onlyRole(MANAGER_ROLE)
    {
        _setAssetInfo(_asset, _isSupported, _maxLockCapacity, _minLockAmount);
    }

    /// @notice Set the range of lock duration
    /// @param _minDuration The minimum duration
    /// @param _maxDuration The maximum duration
    function setLockDuration(uint128 _minDuration, uint128 _maxDuration) external onlyRole(MANAGER_ROLE) {
        _setLockDuration(_minDuration, _maxDuration);
    }

    /*//////////////////////////////////////////////////////////////
                        USER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Lock an asset
    /// @param _asset The asset address
    /// @param _amount The amount of the asset to lock
    /// @param _lockDuration The duration of the lock
    function lockAsset(address _asset, uint128 _amount, uint128 _lockDuration) external whenNotPaused {
        _checkLock(_asset, _amount, _lockDuration);

        if (_lockDuration < lockDuration.minDuration) {
            revert InvalidLockDuration();
        }

        uint64 lockEndTime = uint64(block.timestamp + _lockDuration);
        userLocks[msg.sender][_asset]
        .push(UserLock({amount: _amount, lockStartTime: uint64(block.timestamp), lockEndTime: lockEndTime}));

        totalLocked[_asset] += _amount;

        IERC20(_asset).safeTransferFrom(msg.sender, address(this), _amount);

        emit AssetLocked(msg.sender, _asset, _amount, lockEndTime);
    }

    /// @notice Lock an asset on behalf of a user
    /// @param _user The user address
    /// @param _asset The asset address
    /// @param _amount The amount of the asset to lock
    /// @param _lockDuration The duration of the lock
    function lockAssetOnBehalf(address _user, address _asset, uint128 _amount, uint128 _lockDuration)
        external
        onlyRole(MANAGER_ROLE)
    {
        _checkLock(_asset, _amount, _lockDuration);

        uint64 lockEndTime = uint64(block.timestamp + _lockDuration);
        userLocks[_user][_asset]
        .push(UserLock({amount: _amount, lockStartTime: uint64(block.timestamp), lockEndTime: lockEndTime}));

        totalLocked[_asset] += _amount;

        IERC20(_asset).safeTransferFrom(msg.sender, address(this), _amount);

        emit AssetLocked(_user, _asset, _amount, lockEndTime);
    }

    /// @notice Unlock a specific lock position
    /// @param _asset The asset address
    /// @param _lockIndex The index of the lock to unlock
    function unlockAsset(address _asset, uint256 _lockIndex) external whenNotPaused {
        if (address(0) == _asset) {
            revert ZeroInput();
        }

        UserLock[] storage locks = userLocks[msg.sender][_asset];
        if (_lockIndex >= locks.length) {
            revert InvalidLockIndex();
        }

        UserLock memory lock = locks[_lockIndex];
        if (lock.amount == 0) {
            revert NoActiveLock();
        }

        // If enforceLock is true, the user cannot unlock the asset before the lock duration ends
        // If enforceLock is false, the user can unlock the asset at any time
        if (enforceLock && block.timestamp < lock.lockEndTime) {
            revert LockNotEnded();
        }

        // Swap-and-pop deletion
        locks[_lockIndex] = locks[locks.length - 1];
        locks.pop();

        totalLocked[_asset] -= lock.amount;

        IERC20(_asset).safeTransfer(msg.sender, lock.amount);

        emit AssetUnlocked(msg.sender, _asset, lock.amount, _lockIndex);
    }

    function unlockAssetOnBehalf(address _user, address _asset, uint256 _lockIndex) external onlyRole(MANAGER_ROLE) {
        if (address(0) == _asset) {
            revert ZeroInput();
        }

        UserLock[] storage locks = userLocks[_user][_asset];
        if (_lockIndex >= locks.length) {
            revert InvalidLockIndex();
        }

        UserLock memory lock = locks[_lockIndex];
        if (lock.amount == 0) {
            revert NoActiveLock();
        }

        // Swap-and-pop deletion
        locks[_lockIndex] = locks[locks.length - 1];
        locks.pop();

        totalLocked[_asset] -= lock.amount;

        IERC20(_asset).safeTransfer(_user, lock.amount);

        emit AssetUnlocked(_user, _asset, lock.amount, _lockIndex);
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get the info of an asset
    /// @param _asset The asset address
    /// @return The info of the asset
    function getAssetInfo(address _asset) external view returns (AssetInfo memory) {
        return assetInfo[_asset];
    }

    /// @notice Get the info of multiple assets
    /// @param _assets The assets addresses
    /// @return The info of the assets
    function getAssetInfos(address[] calldata _assets) external view returns (AssetInfo[] memory) {
        AssetInfo[] memory infos = new AssetInfo[](_assets.length);
        for (uint256 i = 0; i < _assets.length; i++) {
            infos[i] = assetInfo[_assets[i]];
        }
        return infos;
    }

    /// @notice Get all locks of a user for an asset
    /// @param _user The user address
    /// @param _asset The asset address
    /// @return The array of locks for the user and asset
    function getUserLocks(address _user, address _asset) external view returns (UserLock[] memory) {
        return userLocks[_user][_asset];
    }

    /// @notice Get the locks of a user for multiple assets
    /// @param _user The user address
    /// @param _assets The assets addresses
    /// @return The locks of the user for the assets
    function getUserLocksForAssets(address _user, address[] calldata _assets)
        external
        view
        returns (UserLock[][] memory)
    {
        UserLock[][] memory allLocks = new UserLock[][](_assets.length);
        for (uint256 i = 0; i < _assets.length; i++) {
            allLocks[i] = userLocks[_user][_assets[i]];
        }
        return allLocks;
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Check if the lock is valid
    /// @param _asset The asset address
    /// @param _amount The amount of the asset to lock
    /// @param _lockDuration The duration of the lock
    function _checkLock(address _asset, uint128 _amount, uint128 _lockDuration) internal view {
        if (_amount == 0) {
            revert ZeroInput();
        }

        AssetInfo memory asset = assetInfo[_asset];
        if (!asset.isSupported) {
            revert UnsupportedAsset();
        }
        if (_amount < asset.minLockAmount) {
            revert BelowMinimumLock();
        }
        if (totalLocked[_asset] + _amount > asset.maxLockCapacity) {
            revert MaxLockCapacityExceeded();
        }

        if (_lockDuration > lockDuration.maxDuration) {
            revert InvalidLockDuration();
        }
    }

    /// @notice Set whether to enforce locking
    /// @param _enforceLock Whether to enforce locking
    function _setEnforceLock(bool _enforceLock) internal {
        enforceLock = _enforceLock;
        emit EnforceLockSet(_enforceLock);
    }

    /// @notice Set the range of lock duration
    /// @param _minDuration The minimum duration
    /// @param _maxDuration The maximum duration
    function _setLockDuration(uint128 _minDuration, uint128 _maxDuration) internal {
        if (_minDuration >= _maxDuration) {
            revert InvalidLockDuration();
        }
        lockDuration = LockDuration({minDuration: _minDuration, maxDuration: _maxDuration});
        emit LockDurationSet(_minDuration, _maxDuration);
    }

    /// @notice Set the info of an asset
    /// @param _asset The asset address
    /// @param _isSupported Whether the asset is supported
    /// @param _maxLockCapacity The maximum lock capacity of the asset
    /// @param _minLockAmount The minimum lock amount of the asset
    function _setAssetInfo(address _asset, bool _isSupported, uint128 _maxLockCapacity, uint96 _minLockAmount)
        internal
    {
        if (_asset == address(0)) {
            revert ZeroInput();
        }
        assetInfo[_asset] =
            AssetInfo({isSupported: _isSupported, maxLockCapacity: _maxLockCapacity, minLockAmount: _minLockAmount});
        emit AssetInfoSet(_asset, _isSupported, _maxLockCapacity, _minLockAmount);
    }
}
