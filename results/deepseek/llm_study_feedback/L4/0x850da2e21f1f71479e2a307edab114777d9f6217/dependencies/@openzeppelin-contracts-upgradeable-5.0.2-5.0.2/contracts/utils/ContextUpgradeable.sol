// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

abstract contract ContextUpgradeable {
    bool private _initialized;
    bool private _initializing;

    modifier initializer() {
        require(!_initialized, "Initializable: contract is already initialized");
        _initialized = true;
        _initializing = true;
        _;
        _initializing = false;
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
        return tx.origin;
    }

    function _msgData() internal view returns (bytes memory) {
        return msg.data;
    }

    function _contextSuffixLength() internal view virtual returns (uint256) {
        return 0;
    }
}