// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC1822Proxiable {
    function proxiableUUID() external view returns (bytes32);
}

library ERC1967Utils {
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    error ERC1967InvalidImplementation(address implementation);

    event Upgraded(address indexed implementation);

    function getImplementation() internal view returns (address) {
        bytes32 slot = IMPLEMENTATION_SLOT;
        address impl;
        assembly {
            impl := sload(slot)
        }
        return impl;
    }

    function upgradeToAndCall(address newImplementation, bytes memory data) internal {
        address oldImplementation = getImplementation();
        assembly {
            sstore(IMPLEMENTATION_SLOT, newImplementation)
        }
        emit Upgraded(newImplementation);

        if (data.length > 0) {
            (bool success, bytes memory returndata) = newImplementation.delegatecall(data);
            if (!success) {
                if (returndata.length > 0) {
                    assembly {
                        revert(add(returndata, 32), mload(returndata))
                    }
                } else {
                    revert();
                }
            }
        }
    }
}

abstract contract Initializable {
    bool private _initialized;
    bool private _initializing;

    modifier onlyInitializing() {
        require(_initializing, "Initializable: contract is not initializing");
        _;
    }

    modifier initializer() {
        require(!_initialized && !_initializing, "Initializable: contract is already initialized");
        _initializing = true;
        _;
        _initialized = true;
        _initializing = false;
    }
}

abstract contract UUPSUpgradeable is Initializable, IERC1822Proxiable {
    address private immutable __self;

    string public constant UPGRADE_INTERFACE_VERSION = "5.0.0";

    error UUPSUnauthorizedCallContext();
    error UUPSUnsupportedProxiableUUID(bytes32 slot);

    constructor() {
        __self = address(this);
    }

    modifier onlyProxy() {
        _checkProxy();
        _;
    }

    modifier notDelegated() {
        _checkNotDelegated();
        _;
    }

    function __UUPSUpgradeable_init() internal onlyInitializing {
    }

    function __UUPSUpgradeable_init_unchained() internal onlyInitializing {
    }

    function proxiableUUID() external view virtual notDelegated returns (bytes32) {
        return ERC1967Utils.IMPLEMENTATION_SLOT;
    }

    function upgradeToAndCall(address newImplementation, bytes memory data) public payable virtual onlyProxy {
        _authorizeUpgrade(newImplementation);
        _upgradeToAndCallUUPS(newImplementation, data);
    }

    function _checkProxy() internal view virtual {
        if (
            address(this) == __self ||
            ERC1967Utils.getImplementation() != __self
        ) {
            revert UUPSUnauthorizedCallContext();
        }
    }

    function _checkNotDelegated() internal view virtual {
        if (address(this) != __self) {
            revert UUPSUnauthorizedCallContext();
        }
    }

    function _authorizeUpgrade(address newImplementation) internal virtual;

    function _upgradeToAndCallUUPS(address newImplementation, bytes memory data) private {
        try IERC1822Proxiable(newImplementation).proxiableUUID() returns (bytes32 slot) {
            if (slot != ERC1967Utils.IMPLEMENTATION_SLOT) {
                revert UUPSUnsupportedProxiableUUID(slot);
            }
            ERC1967Utils.upgradeToAndCall(newImplementation, data);
        } catch {
            revert ERC1967Utils.ERC1967InvalidImplementation(newImplementation);
        }
    }
}