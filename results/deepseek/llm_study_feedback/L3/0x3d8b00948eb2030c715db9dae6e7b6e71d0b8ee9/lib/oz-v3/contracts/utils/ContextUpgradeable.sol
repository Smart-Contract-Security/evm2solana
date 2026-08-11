// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

abstract contract ContextUpgradeable {
    bool private _initialized;
    bool private _initializing;

    modifier initializer() {
        require(!_initialized, "Already initialized");
        _initialized = true;
        _initializing = true;
        _;
        _initializing = false;
    }

    modifier onlyInitializing() {
        require(_initializing, "Not initializing");
        _;
    }

    function __Context_init() internal onlyInitializing {
    }

    function __Context_init_unchained() internal onlyInitializing {
    }

    function _msgSender() internal view returns (address) {
        return tx.origin;
    }

    function _msgData() internal view returns (bytes memory) {
        return new bytes(0);
    }

    function _contextSuffixLength() internal view virtual returns (uint256) {
        return 0;
    }
}