// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

abstract contract UUPSUpgradeable {
    address private immutable __self;

    bytes32 private constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    constructor() {
        __self = address(this);
    }

    string public constant UPGRADE_INTERFACE_VERSION = "5.0.0";

    string constant UUPSUnauthorizedCallContext = "UUPSUnauthorizedCallContext";
    string constant UUPSUnsupportedProxiableUUID = "UUPSUnsupportedProxiableUUID";
    string constant ERC1967InvalidImplementation = "ERC1967InvalidImplementation";

    modifier onlyProxy() {
        _checkProxy();
        _;
    }

    modifier notDelegated() {
        _checkNotDelegated();
        _;
    }

    function proxiableUUID() external view notDelegated returns (bytes32) {
        return IMPLEMENTATION_SLOT;
    }

    function upgradeToAndCall(address newImplementation, bytes memory data) public payable virtual onlyProxy {
        _authorizeUpgrade(newImplementation);
        _upgradeToAndCallUUPS(newImplementation, data);
    }

    function _checkProxy() internal view virtual {
        if (
            address(this) == __self ||
            _getImplementation() != __self
        ) {
            revert(UUPSUnauthorizedCallContext);
        }
    }

    function _checkNotDelegated() internal view virtual {
        if (address(this) != __self) {
            revert(UUPSUnauthorizedCallContext);
        }
    }

    function _authorizeUpgrade(address newImplementation) internal virtual;

    function _upgradeToAndCallUUPS(address newImplementation, bytes memory data) private {
        bytes32 slot = UUPSUpgradeable(newImplementation).proxiableUUID{accounts: [newImplementation]}();
        if (slot != IMPLEMENTATION_SLOT) {
            revert(UUPSUnsupportedProxiableUUID);
        }
        _upgradeToAndCall(newImplementation, data);
    }

    function _getImplementation() internal view returns (address) {
        bytes32 slot = IMPLEMENTATION_SLOT;
        address impl;
        assembly {
            impl := sload(slot)
        }
        return impl;
    }

    function _upgradeToAndCall(address newImplementation, bytes memory data) internal {
        bytes32 slot = IMPLEMENTATION_SLOT;
        assembly {
            sstore(slot, newImplementation)
        }
        if (data.length > 0) {
            (bool success, bytes memory returndata) = newImplementation.call{value: 0}(data);
            if (!success) {
                if (returndata.length > 0) {
                    assembly {
                        revert(add(returndata, 32), mload(returndata))
                    }
                } else {
                    revert(ERC1967InvalidImplementation);
                }
            }
        }
    }
}