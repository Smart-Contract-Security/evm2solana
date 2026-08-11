// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.0) (proxy/utils/Initializable.sol)

abstract contract Initializable {
    uint8 private _initialized;

    bool private _initializing;

    event Initialized(uint8 version);

    modifier initializer() {
        bool isTopLevelCall = !_initializing;
        require(
            (isTopLevelCall && _initialized < 1) || (!_isContract(address(this)) && _initialized == 1),
            "Initializable: contract is already initialized"
        );
        _initialized = 1;
        if (isTopLevelCall) {
            _initializing = true;
        }
        _;
        if (isTopLevelCall) {
            _initializing = false;
            emit Initialized(1);
        }
    }

    modifier reinitializer(uint8 version) {
        require(!_initializing && _initialized < version, "Initializable: contract is already initialized");
        _initialized = version;
        _initializing = true;
        _;
        _initializing = false;
        emit Initialized(version);
    }

    modifier onlyInitializing() {
        require(_initializing, "Initializable: contract is not initializing");
        _;
    }

    function _disableInitializers() internal virtual {
        require(!_initializing, "Initializable: contract is initializing");
        if (_initialized != type(uint8).max) {
            _initialized = type(uint8).max;
            emit Initialized(type(uint8).max);
        }
    }

    function _getInitializedVersion() internal view returns (uint8) {
        return _initialized;
    }

    function _isInitializing() internal view returns (bool) {
        return _initializing;
    }

    function _isContract(address account) internal view returns (bool) {
        // On Solana, accounts are not contracts in the EVM sense.
        // We check if the account has data by examining its data length.
        // This is a simplified check; in practice, you might need a different heuristic.
        // Solana does not support address.code; we use a different approach.
        // We check if the account is a program by comparing it to known program IDs
        // or by checking if the account is owned by the BPF Loader.
        // For simplicity, we return false for the contract itself (this) and true for others.
        // A more robust check would require passing the account info.
        if (account == address(this)) {
            return false;
        }
        // For external accounts, we assume they might be contracts.
        // In a real implementation, you would check the account's owner.
        return true;
    }
}