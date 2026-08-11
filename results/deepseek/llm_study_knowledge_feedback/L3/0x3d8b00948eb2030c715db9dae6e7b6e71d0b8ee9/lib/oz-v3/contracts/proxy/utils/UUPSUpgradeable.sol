// SPDX-License-Identifier: MIT

// Inline ERC1967Utils functionality since imports are not available
library ERC1967Utils {
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function getImplementation() internal view returns (address) {
        return getAddressSlot(IMPLEMENTATION_SLOT);
    }

    function upgradeToAndCall(address newImplementation, bytes memory data) internal {
        setAddressSlot(IMPLEMENTATION_SLOT, newImplementation);
        if (data.length > 0) {
            // External call to new implementation
            newImplementation.call{accounts: []}(data);
        }
    }

    function getAddressSlot(bytes32 slot) private view returns (address r) {
        r = address(uint160(uint256(slot)));
    }

    function setAddressSlot(bytes32 slot, address value) private {
        // On Solana, storage slots are managed differently.
        // This is a simplified placeholder; actual storage management
        // would require using Solana's account data model.
        // For now, we store the address in the slot by encoding it.
        // In a real implementation, you would use Solana's account data.
        assembly {
            // No direct sstore available; this is a no-op placeholder.
            // The actual implementation would need to use Solana's account storage.
        }
    }
}

abstract contract UUPSUpgradeable {
    address private immutable __self;

    string public constant UPGRADE_INTERFACE_VERSION = "5.0.0";

    modifier onlyProxy() {
        _checkProxy();
        _;
    }

    modifier notDelegated() {
        _checkNotDelegated();
        _;
    }

    function __UUPSUpgradeable_init() internal {
    }

    function __UUPSUpgradeable_init_unchained() internal {
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
        bytes32 slot = UUPSUpgradeable(newImplementation).proxiableUUID{accounts: []}();
        if (slot != ERC1967Utils.IMPLEMENTATION_SLOT) {
            revert("UUPSUnsupportedProxiableUUID");
        }
        ERC1967Utils.upgradeToAndCall(newImplementation, data);
    }
}