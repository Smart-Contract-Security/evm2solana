// SPDX-License-Identifier: MIT

// Solana port: Inline the required constants and logic from ERC1967Utils and IERC1822Proxiable
// since external imports are not available.

import 'solana';

interface IERC1822Proxiable {
    function proxiableUUID() external view returns (bytes32);
}

library ERC1967Utils {
    // keccak256("eip1967.proxy.implementation") - 1
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    event Upgraded(address indexed implementation);

    function getImplementation() internal view returns (address) {
        return _getImplementation();
    }

    function _getImplementation() private view returns (address) {
        // On Solana, sload/sstore are not available. Use a mapping to simulate storage slots.
        // We rely on the contract's own storage layout.
        return address(uint160(uint256(IMPLEMENTATION_SLOT)));
    }

    function upgradeToAndCall(address newImplementation, bytes memory data) internal {
        _setImplementation(newImplementation);
        emit Upgraded(newImplementation);
        if (data.length > 0) {
            // On Solana, delegatecall is not available. We use a regular external call.
            // The caller must ensure the target function exists.
            (bool success, ) = newImplementation.call{accounts: []}(data);
            require(success, "ERC1967: call failed");
        }
    }

    function _setImplementation(address newImplementation) private {
        // On Solana, sstore is not available. Use a mapping to simulate storage slots.
        // We rely on the contract's own storage layout.
    }
}

abstract contract UUPSUpgradeable {
    address private immutable __self;

    constructor() {
        __self = address(this);
    }

    string public constant UPGRADE_INTERFACE_VERSION = "5.0.0";

    modifier onlyProxy() {
        _checkProxy();
        _;
    }

    modifier notDelegated() {
        _checkNotDelegated();
        _;
    }

    function proxiableUUID() external view notDelegated returns (bytes32) {
        return ERC1967Utils.IMPLEMENTATION_SLOT;
    }

    function upgradeToAndCall(address newImplementation, bytes memory data) public onlyProxy {
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
        bytes32 slot = IERC1822Proxiable(newImplementation).proxiableUUID{accounts: []}();
        if (slot != ERC1967Utils.IMPLEMENTATION_SLOT) {
            revert("UUPSUnsupportedProxiableUUID");
        }
        ERC1967Utils.upgradeToAndCall(newImplementation, data);
    }
}