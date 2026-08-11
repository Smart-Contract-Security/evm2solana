// SPDX-License-Identifier: MIT

library ERC1967Utils {
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
    bytes32 internal constant BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    event Upgraded(address indexed implementation);
    event AdminChanged(address indexed previousAdmin, address indexed newAdmin);
    event BeaconUpgraded(address indexed beacon);

    // Storage mapping for address slots
    mapping(bytes32 => address) private _addressStorage;

    function getImplementation() internal view returns (address) {
        return getAddressSlot(IMPLEMENTATION_SLOT);
    }

    function _setImplementation(address newImplementation) private {
        // On Solana, we cannot check code length of an arbitrary address.
        // We assume the caller validates the implementation account.
        setAddressSlot(IMPLEMENTATION_SLOT, newImplementation);
    }

    function upgradeToAndCall(address newImplementation, bytes memory data) internal {
        _setImplementation(newImplementation);
        emit Upgraded(newImplementation);

        if (data.length > 0) {
            (bool success, ) = newImplementation.call{accounts: []}(data);
            require(success, "ERC1967: delegate call failed");
        }
    }

    function getAdmin() internal view returns (address) {
        return getAddressSlot(ADMIN_SLOT);
    }

    function _setAdmin(address newAdmin) private {
        require(newAdmin != address(0), "ERC1967: invalid admin");
        setAddressSlot(ADMIN_SLOT, newAdmin);
    }

    function changeAdmin(address newAdmin) internal {
        emit AdminChanged(getAdmin(), newAdmin);
        _setAdmin(newAdmin);
    }

    function getBeacon() internal view returns (address) {
        return getAddressSlot(BEACON_SLOT);
    }

    function _setBeacon(address newBeacon) private {
        // On Solana, we cannot check code length of an arbitrary address.
        // We assume the caller validates the beacon account.
        setAddressSlot(BEACON_SLOT, newBeacon);

        // IBeacon interface is not available; we inline the call.
        // The beacon must have an 'implementation()' function returning address.
        (bool ok, bytes memory ret) = newBeacon.call{accounts: []}(abi.encodeWithSignature("implementation()"));
        require(ok, "ERC1967: beacon call failed");
        address beaconImplementation = abi.decode(ret, (address));
        // We cannot check code length; assume valid.
    }

    function upgradeBeaconToAndCall(address newBeacon, bytes memory data) internal {
        _setBeacon(newBeacon);
        emit BeaconUpgraded(newBeacon);

        if (data.length > 0) {
            (bool ok, bytes memory ret) = newBeacon.call{accounts: []}(abi.encodeWithSignature("implementation()"));
            require(ok, "ERC1967: beacon call failed");
            address impl = abi.decode(ret, (address));
            (bool success, ) = impl.call{accounts: []}(data);
            require(success, "ERC1967: delegate call failed");
        }
    }

    function getAddressSlot(bytes32 slot) private view returns (address) {
        return _addressStorage[slot];
    }

    function setAddressSlot(bytes32 slot, address value) private {
        _addressStorage[slot] = value;
    }
}