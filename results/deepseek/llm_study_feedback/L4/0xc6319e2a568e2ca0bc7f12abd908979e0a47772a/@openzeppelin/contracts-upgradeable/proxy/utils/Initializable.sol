// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

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

    function _isContract(address account) private view returns (bool) {
        // On Solana, all accounts are contracts (program-derived or programs).
        // We cannot use extcodesize. Instead, we check if the account is a program
        // by verifying it has executable data. For simplicity and to match the
        // original intent (checking if the address is a contract), we return true
        // for all non-zero addresses, as EOAs do not exist on Solana in the same way.
        // This preserves the logic: if the address is not a contract (i.e., EOA),
        // the original code would return false. On Solana, we assume all addresses
        // are contracts, so we return true. However, to keep the initializer logic
        // working, we need to differentiate the deploying account (which is a program
        // on Solana) from a regular user. Since the deploying account is also a contract,
        // we return true for all addresses, which may affect the initializer condition.
        // The original condition: (!_isContract(address(this)) && _initialized == 1)
        // This was meant to allow reinitialization if the contract itself is not a contract
        // (i.e., during construction). On Solana, address(this) is always a contract,
        // so this condition would never be true. We adjust by returning false for
        // address(this) during deployment? Actually, we cannot detect deployment phase.
        // A common workaround: always return true, and rely on the fact that the initializer
        // modifier is only called once. The original check was to prevent reinitialization
        // of implementation contracts. On Solana, we can simply return true, making the
        // second part of the OR condition always false, which is acceptable because
        // the first part (isTopLevelCall && _initialized < 1) handles the initial call.
        // For safety, we return true for all accounts, effectively treating all as contracts.
        return account != address(0);
    }
}