// SPDX-License-Identifier: MIT

import {AccountMeta} from 'solana';

interface IERC1822Proxiable {
    function proxiableUUID() external view returns (bytes32);
}

abstract contract UUPSUpgradeable is IERC1822Proxiable {
    address private immutable __self;

    string public constant UPGRADE_INTERFACE_VERSION = "5.0.0";

    bytes32 private constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    modifier onlyProxy() {
        _checkProxy();
        _;
    }

    modifier notDelegated() {
        _checkNotDelegated();
        _;
    }

    modifier onlyInitializing() {
        _;
    }

    constructor() {
        __self = address(this);
    }

    function initialize() internal onlyInitializing {
    }

    function initialize_unchained() internal onlyInitializing {
    }

    function proxiableUUID() external view virtual notDelegated returns (bytes32) {
        return IMPLEMENTATION_SLOT;
    }

    function upgradeToAndCall(address newImplementation, bytes memory data) public virtual onlyProxy {
        _authorizeUpgrade(newImplementation);
        _upgradeToAndCallUUPS(newImplementation, data);
    }

    function _checkProxy() internal view virtual {
        if (
            address(this) == __self ||
            getImplementation() != __self
        ) {
            revert("UUPSUnauthorizedCallContext");
        }
    }

    function _checkNotDelegated() internal view virtual {
        if (address(this) != __self) {
            revert("UUPSUnauthorizedCallContext");
        }
    }

    function _authorizeUpgrade(address newImplementation) internal virtual;

    function _upgradeToAndCallUUPS(address newImplementation, bytes memory data) private {
        bytes32 slot = IERC1822Proxiable(newImplementation).proxiableUUID();
        if (slot != IMPLEMENTATION_SLOT) {
            revert("UUPSUnsupportedProxiableUUID");
        }
        upgradeToAndCallInternal(newImplementation, data);
    }

    function getImplementation() internal view returns (address) {
        return _implementation;
    }

    function upgradeToAndCallInternal(address newImplementation, bytes memory data) internal {
        _implementation = newImplementation;
        if (data.length > 0) {
            (bool success, ) = newImplementation.call{accounts: []}(data);
            require(success, "delegatecall failed");
        }
    }

    address private _implementation;
}