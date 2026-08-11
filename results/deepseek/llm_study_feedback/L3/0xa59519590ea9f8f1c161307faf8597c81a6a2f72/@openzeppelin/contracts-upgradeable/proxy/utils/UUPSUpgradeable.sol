// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC1822Proxiable {
    function proxiableUUID() external view returns (bytes32);
}

library ERC1967Utils {
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    event Upgraded(address indexed implementation);

    function getImplementation() internal view returns (address) {
        return address(uint160(uint256(IMPLEMENTATION_SLOT)));
    }

    function _setImplementation(address newImplementation) internal {
        // In Solana, storage is handled differently. This is a placeholder.
        // The actual implementation address is stored in the contract's data account.
        // For a proper port, a dedicated storage mechanism would be needed.
        // Here we simply emit an event to indicate the change.
        emit Upgraded(newImplementation);
    }

    function upgradeToAndCall(address newImplementation, bytes memory data) internal {
        address oldImplementation = getImplementation();
        _setImplementation(newImplementation);
        emit Upgraded(newImplementation);
        if (data.length > 0) {
            (bool success, bytes memory returndata) = newImplementation.call{value: 0}(data);
            if (!success) {
                if (returndata.length > 0) {
                    assembly {
                        revert(add(returndata, 0x20), mload(returndata))
                    }
                } else {
                    revert("ERC1967Utils: low-level delegatecall failed");
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
        require(!_initialized, "Initializable: contract is already initialized");
        _initialized = true;
        _initializing = true;
        _;
        _initializing = false;
    }
}

abstract contract UUPSUpgradeable is Initializable, IERC1822Proxiable {
    address private immutable __self;

    string public constant UPGRADE_INTERFACE_VERSION = "5.0.0";

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

    function upgradeToAndCall(address newImplementation, bytes memory data) public virtual onlyProxy {
        _authorizeUpgrade(newImplementation);
        _upgradeToAndCallUUPS(newImplementation, data);
    }

    function _checkProxy() internal view virtual {
        if (
            address(this) == __self ||
            ERC1967Utils.getImplementation() != __self
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
        if (slot != ERC1967Utils.IMPLEMENTATION_SLOT) {
            revert("UUPSUnsupportedProxiableUUID");
        }
        ERC1967Utils.upgradeToAndCall(newImplementation, data);
    }
}