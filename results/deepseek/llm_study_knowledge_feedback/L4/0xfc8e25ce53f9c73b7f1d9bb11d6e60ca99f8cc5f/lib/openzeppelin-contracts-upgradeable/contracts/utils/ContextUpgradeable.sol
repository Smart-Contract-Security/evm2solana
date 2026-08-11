// SPDX-License-Identifier: MIT

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

    function _msgSender() internal view virtual returns (address) {
        return tx.accounts.dataAccount.key;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    function _contextSuffixLength() internal view virtual returns (uint64) {
        return 0;
    }
}