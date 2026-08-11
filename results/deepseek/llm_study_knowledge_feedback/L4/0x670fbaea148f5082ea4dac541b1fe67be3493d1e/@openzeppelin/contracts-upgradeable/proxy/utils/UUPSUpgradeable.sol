// SPDX-License-Identifier: MIT

import {Initializable} from "./Initializable.sol";

abstract contract UUPSUpgradeable is Initializable {
    address private immutable __self;

    string public constant UPGRADE_INTERFACE_VERSION = "5.0.0";

    bytes32 public constant IMPLEMENTATION_SLOT = hex"360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";

    modifier onlyProxy() {
        _checkProxy();
        _;
    }

    modifier notDelegated() {
        _checkNotDelegated();
        _;
    }

    constructor() {
        __self = address(this);
    }

    function __UUPSUpgradeable_init() internal onlyInitializing {
    }

    function __UUPSUpgradeable_init_unchained() internal onlyInitializing {
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

    function getImplementation() internal view returns (address) {
        return _implementation;
    }

    address private _implementation;

    function _upgradeToAndCallUUPS(address newImplementation, bytes memory data) private {
        bytes32 slot = UUPSUpgradeable(newImplementation).proxiableUUID{accounts: [newImplementation]}();
        if (slot != IMPLEMENTATION_SLOT) {
            revert("UUPSUnsupportedProxiableUUID");
        }
        upgradeToAndCallInternal(newImplementation, data);
    }

    function upgradeToAndCallInternal(address newImplementation, bytes memory data) internal {
        _implementation = newImplementation;
        if (data.length > 0) {
            (bool success, bytes memory returndata) = newImplementation.call{accounts: [newImplementation]}(data);
            require(success, "call failed");
        }
    }
}