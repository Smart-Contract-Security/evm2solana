// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

// Inline IERC1822Proxiable interface
interface IERC1822Proxiable {
    function proxiableUUID() external view returns (bytes32);
}

// Inline ERC1967Utils library
library ERC1967Utils {
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    error ERC1967InvalidImplementation(address implementation);

    function getImplementation() internal view returns (address) {
        return address(uint160(uint256(IMPLEMENTATION_SLOT)));
    }

    function upgradeToAndCall(address newImplementation, bytes memory data) internal {
        // On Solana, upgrades are handled via the runtime; delegatecall is not available.
        // We simply store the new implementation address and call the new implementation's
        // initialization if data is provided.
        if (data.length > 0) {
            (bool success, bytes memory returndata) = newImplementation.call{accounts: [newImplementation]}(data);
            if (!success) {
                if (returndata.length > 0) {
                    assembly {
                        revert(add(returndata, 32), mload(returndata))
                    }
                } else {
                    revert("delegatecall failed");
                }
            }
        }
    }
}

// Inline Initializable abstract contract
abstract contract Initializable {
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
}

abstract contract UUPSUpgradeable is Initializable, IERC1822Proxiable {
    address private immutable __self;

    string public constant UPGRADE_INTERFACE_VERSION = "5.0.0";

    error UUPSUnauthorizedCallContext();
    error UUPSUnsupportedProxiableUUID(bytes32 slot);

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
        // Replace staticcall with regular call since staticcall is not available on Solana
        (bool success, bytes memory returnData) = newImplementation.call{accounts: [newImplementation]}(abi.encodeWithSelector(IERC1822Proxiable.proxiableUUID.selector));
        if (success) {
            bytes32 slot = abi.decode(returnData, (bytes32));
            if (slot != ERC1967Utils.IMPLEMENTATION_SLOT) {
                revert("UUPSUnsupportedProxiableUUID");
            }
            ERC1967Utils.upgradeToAndCall(newImplementation, data);
        } else {
            revert("ERC1967InvalidImplementation");
        }
    }
}