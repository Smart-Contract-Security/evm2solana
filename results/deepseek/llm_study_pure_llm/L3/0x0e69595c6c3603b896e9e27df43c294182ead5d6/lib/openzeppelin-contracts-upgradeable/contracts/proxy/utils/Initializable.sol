// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

abstract contract Initializable {
    /**
     * @dev Indicates that the contract has been initialized.
     */
    bool private _initialized;

    /**
     * @dev Indicates that the contract is in the process of being initialized.
     */
    bool private _initializing;

    /**
     * @dev Modifier to protect an initializer function from being invoked twice.
     */
    modifier initializer() {
        // If the contract is initializing we ignore whether _initialized is set in order to support multiple
        // inheritance patterns, but we only do this in the context of a constructor, because in other contexts the
        // contract may have been reentered.
        require(_initializing ? _isConstructor() : !_initialized, "Initializable: contract is already initialized");

        bool isTopLevelCall = !_initializing;
        if (isTopLevelCall) {
            _initializing = true;
            _initialized = true;
        }

        _;

        if (isTopLevelCall) {
            _initializing = false;
        }
    }

    /**
     * @dev Modifier to protect an initialization function from being invoked twice.
     */
    modifier reinitializer(uint64 version) {
        // Solidity sets the version to 1 when not specified, and to type(uint64).max when max is specified.
        // If version is 1, then this is an initializer, and we need to check _initialized.
        // If version is > 1, then we need to check _initialized and _initializing.
        if (version == 1) {
            require(!_initialized, "Initializable: contract is already initialized");
        } else {
            require(!_initializing && !_initialized, "Initializable: contract is already initialized");
        }

        bool isTopLevelCall = !_initializing;
        if (isTopLevelCall) {
            _initializing = true;
            _initialized = true;
        }

        _;

        if (isTopLevelCall) {
            _initializing = false;
        }
    }

    /**
     * @dev Modifier to protect an initialization function from being invoked twice.
     */
    modifier onlyInitializing() {
        require(_initializing, "Initializable: contract is not initializing");
        _;
    }

    /**
     * @dev Returns true if and only if the function is running in the constructor
     */
    function _isConstructor() private view returns (bool) {
        // extcodesize checks the size of the code at an address, for a contract under construction it is 0
        uint256 cs;
        assembly {
            cs := extcodesize(address())
        }
        return cs == 0;
    }

    /**
     * @dev Locks the contract, preventing any future reinitialization. This cannot be part of an initializer call.
     * Calling this in the constructor will prevent the contract from being initialized or reinitialized.
     * It is recommended to use this to lock implementation contracts that are designed to be called through proxies.
     */
    function _disableInitializers() internal virtual {
        require(!_initializing, "Initializable: contract is initializing");
        if (_initialized) {
            return;
        }
        _initialized = true;
    }
}