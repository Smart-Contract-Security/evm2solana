// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.3.0) (proxy/utils/Initializable.sol)

abstract contract Initializable {
    struct InitializableStorage {
        uint64 _initialized;
        bool _initializing;
    }

    bytes32 private constant INITIALIZABLE_STORAGE = 0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;

    event Initialized(uint64 version);

    modifier initializer() {
        InitializableStorage storage $ = _getInitializableStorage();

        bool isTopLevelCall = !$._initializing;
        uint64 initialized = $._initialized;

        bool initialSetup = initialized == 0 && isTopLevelCall;
        // On Solana, address.code is not supported. We use a different approach:
        // During construction, the data account is being initialized for the first time.
        // We check if the initialized flag is 1 and we are in a top-level call (not reentrant).
        // Since we cannot check code length, we rely on the initialized flag being set to 1
        // during construction by the constructor itself.
        bool construction = initialized == 1 && isTopLevelCall && !initialSetup;

        if (!initialSetup && !construction) {
            revert("InvalidInitialization");
        }
        $._initialized = 1;
        if (isTopLevelCall) {
            $._initializing = true;
        }
        _;
        if (isTopLevelCall) {
            $._initializing = false;
            emit Initialized(1);
        }
    }

    modifier reinitializer(uint64 version) {
        InitializableStorage storage $ = _getInitializableStorage();

        if ($._initializing || $._initialized >= version) {
            revert("InvalidInitialization");
        }
        $._initialized = version;
        $._initializing = true;
        _;
        $._initializing = false;
        emit Initialized(version);
    }

    modifier onlyInitializing() {
        _checkInitializing();
        _;
    }

    function _checkInitializing() internal view virtual {
        if (!_isInitializing()) {
            revert("NotInitializing");
        }
    }

    function _disableInitializers() internal virtual {
        InitializableStorage storage $ = _getInitializableStorage();

        if ($._initializing) {
            revert("InvalidInitialization");
        }
        if ($._initialized != type(uint64).max) {
            $._initialized = type(uint64).max;
            emit Initialized(type(uint64).max);
        }
    }

    function _getInitializedVersion() internal view returns (uint64) {
        return _getInitializableStorage()._initialized;
    }

    function _isInitializing() internal view returns (bool) {
        return _getInitializableStorage()._initializing;
    }

    function _initializableStorageSlot() internal pure virtual returns (bytes32) {
        return INITIALIZABLE_STORAGE;
    }

    function _getInitializableStorage() private pure returns (InitializableStorage storage $) {
        bytes32 slot = _initializableStorageSlot();
        assembly {
            $.slot := slot
        }
    }
}