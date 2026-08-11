// SPDX-License-Identifier: MIT

library ERC1967Utils {
    event Upgraded(address implementation);

    event AdminChanged(address previousAdmin, address newAdmin);

    event BeaconUpgraded(address beacon);

    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    bytes32 internal constant BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    function getImplementation() internal view returns (address) {
        return getAddressSlot(IMPLEMENTATION_SLOT).value;
    }

    function _setImplementation(address newImplementation) private {
        // On Solana, address.code is not supported.
        // We assume the caller has validated the implementation account.
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
            revert("ERC1967InvalidAdmin");
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
        // On Solana, address.code is not supported.
        // We assume the caller has validated the beacon account.
        getAddressSlot(BEACON_SLOT).value = newBeacon;

        // IBeacon is not available on Solana.
        // The beacon implementation check is removed.
        // The caller must ensure the beacon provides a valid implementation.
    }

    function upgradeBeaconToAndCall(address newBeacon, bytes memory data) internal {
        _setBeacon(newBeacon);
        emit BeaconUpgraded(newBeacon);

        if (data.length > 0) {
            // IBeacon is not available on Solana.
            // The implementation address must be obtained through other means.
            // For now, we revert to indicate this path is unsupported.
            revert("Beacon upgrade with data not supported on Solana");
        } else {
            _checkNonPayable();
        }
    }

    function _checkNonPayable() private {
        // msg.value is not supported on Solana, so this check is removed.
        // The payable keyword has no effect on Solana.
    }

    struct AddressSlot {
        address value;
    }

    function getAddressSlot(bytes32 slot) private pure returns (AddressSlot storage r) {
        assembly {
            r.slot := slot
        }
    }

    function functionDelegateCall(address target, bytes memory data) private {
        // delegatecall is not available on Solana.
        // This is a placeholder that reverts to indicate the operation is unsupported.
        revert("delegatecall not supported on Solana");
    }
}