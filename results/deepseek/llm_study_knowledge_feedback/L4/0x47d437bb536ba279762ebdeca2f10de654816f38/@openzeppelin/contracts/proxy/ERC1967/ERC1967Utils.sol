// SPDX-License-Identifier: MIT

library ERC1967Utils {
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
    bytes32 internal constant BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    event Upgraded(address indexed implementation);
    event AdminChanged(address previousAdmin, address newAdmin);
    event BeaconUpgraded(address indexed beacon);

    function getImplementation() internal view returns (address) {
        return getAddressSlot(IMPLEMENTATION_SLOT).value;
    }

    function _setImplementation(address newImplementation) private {
        // On Solana, address.code is not available. We skip the code length check.
        getAddressSlot(IMPLEMENTATION_SLOT).value = newImplementation;
    }

    function upgradeToAndCall(address newImplementation, bytes memory data) internal {
        _setImplementation(newImplementation);
        emit Upgraded(newImplementation);

        if (data.length > 0) {
            functionDelegateCall(newImplementation, data);
        } else {
            _checkNonPayable();
        }
    }

    function getAdmin() internal view returns (address) {
        return getAddressSlot(ADMIN_SLOT).value;
    }

    function _setAdmin(address newAdmin) private {
        if (newAdmin == address(0)) {
            revert("ERC1967: invalid admin");
        }
        getAddressSlot(ADMIN_SLOT).value = newAdmin;
    }

    function changeAdmin(address newAdmin) internal {
        emit AdminChanged(getAdmin(), newAdmin);
        _setAdmin(newAdmin);
    }

    function getBeacon() internal view returns (address) {
        return getAddressSlot(BEACON_SLOT).value;
    }

    function _setBeacon(address newBeacon) private {
        // On Solana, address.code is not available. We skip the code length check.
        getAddressSlot(BEACON_SLOT).value = newBeacon;

        // IBeacon is not available; we skip the implementation check.
    }

    function upgradeBeaconToAndCall(address newBeacon, bytes memory data) internal {
        _setBeacon(newBeacon);
        emit BeaconUpgraded(newBeacon);

        if (data.length > 0) {
            // IBeacon is not available; we skip the implementation call.
            // functionDelegateCall(IBeacon(newBeacon).implementation(), data);
        } else {
            _checkNonPayable();
        }
    }

    function _checkNonPayable() private {
        // msg.value is not supported on Solana; value transfers are handled via the runtime.
        // The check is removed as it has no effect.
    }

    struct AddressSlot {
        address value;
    }

    function getAddressSlot(bytes32 slot) private pure returns (AddressSlot storage r) {
        assembly {
            r.slot := slot
        }
    }

    function functionDelegateCall(address target, bytes memory data) private returns (bytes memory) {
        // delegatecall is not available on Solana. We revert with an error.
        revert("ERC1967: delegatecall not supported on Solana");
    }
}