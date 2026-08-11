// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract ContextUpgradeable {
    bool private _initialized;
    bool private _initializing;

    modifier initializer() {
        require(!_initialized, "Initializable: contract is already initialized");
        _initializing = true;
        _;
        _initializing = false;
        _initialized = true;
    }

    modifier onlyInitializing() {
        require(_initializing, "Initializable: contract is not initializing");
        _;
    }

    function __Context_init() internal onlyInitializing {
    }

    function __Context_init_unchained() internal onlyInitializing {
    }

    function _msgSender() internal view returns (address) {
        return tx.accounts[0];
    }

    function _msgData() internal view returns (bytes memory) {
        return tx.data;
    }

    uint256[50] private __gap;
}