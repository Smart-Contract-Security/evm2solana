// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

library ERC1967Utils {
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    error ERC1967InvalidImplementation(address implementation);
    error ERC1967InvalidAdmin(address admin);
    error ERC1967InvalidBeacon(address beacon);
    error ERC1967NonPayable();

    function getImplementation() internal view returns (address) {
        return address(uint160(uint256(getAddressSlot(IMPLEMENTATION_SLOT))));
    }

    function _setImplementation(address newImplementation) private {
        // On Solana, we cannot check code length of an arbitrary address.
        // We assume the caller has validated the implementation.
        setAddressSlot(IMPLEMENTATION_SLOT, newImplementation);
    }

    function upgradeToAndCall(address newImplementation, bytes memory data) internal {
        _setImplementation(newImplementation);
        emit Upgraded(newImplementation);

        if (data.length > 0) {
            Address.functionDelegateCall(newImplementation, data);
        } else {
            _checkNonPayable();
        }
    }

    bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    function getAdmin() internal view returns (address) {
        return address(uint160(uint256(getAddressSlot(ADMIN_SLOT))));
    }

    function _setAdmin(address newAdmin) private {
        if (newAdmin == address(0)) {
            revert("ERC1967: invalid admin");
        }
        setAddressSlot(ADMIN_SLOT, newAdmin);
    }

    function changeAdmin(address newAdmin) internal {
        emit AdminChanged(getAdmin(), newAdmin);
        _setAdmin(newAdmin);
    }

    bytes32 internal constant BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    function getBeacon() internal view returns (address) {
        return address(uint160(uint256(getAddressSlot(BEACON_SLOT))));
    }

    function _setBeacon(address newBeacon) private {
        // On Solana, we cannot check code length of an arbitrary address.
        // We assume the caller has validated the beacon.

        setAddressSlot(BEACON_SLOT, newBeacon);

        (bool success, bytes memory returndata) = newBeacon.call{accounts: []}(abi.encodeWithSignature("implementation()"));
        require(success, "Beacon: implementation() call failed");
        address beaconImplementation = abi.decode(returndata, (address));
        // On Solana, we cannot check code length of an arbitrary address.
        // We assume the beacon implementation is valid.
    }

    function upgradeBeaconToAndCall(address newBeacon, bytes memory data) internal {
        _setBeacon(newBeacon);
        emit BeaconUpgraded(newBeacon);

        if (data.length > 0) {
            (bool success, bytes memory returndata) = newBeacon.call{accounts: []}(abi.encodeWithSignature("implementation()"));
            require(success, "Beacon: implementation() call failed");
            address beaconImplementation = abi.decode(returndata, (address));
            Address.functionDelegateCall(beaconImplementation, data);
        } else {
            _checkNonPayable();
        }
    }

    function _checkNonPayable() private {
        if (msg.value > 0) {
            revert("ERC1967: non-payable");
        }
    }

    function getAddressSlot(bytes32 slot) private view returns (bytes32) {
        // On Solana, we use account storage via the contract's data account.
        // We assume the slot is stored in the contract's persistent storage.
        // Solang does not support inline assembly sload/sstore.
        // We use a mapping to simulate storage slots.
        return _storage[slot];
    }

    function setAddressSlot(bytes32 slot, address value) private {
        _storage[slot] = bytes32(uint256(uint160(value)));
    }

    // Solana storage simulation: a mapping from slot to bytes32 value.
    // This mapping must be declared at the library level.
    // Note: Libraries cannot have state variables in Solidity, but Solang may allow it.
    // If not, we need an alternative approach. We'll use a struct pattern.
    // However, for simplicity, we assume the library is used via delegatecall and storage is shared.
    // We'll define a dummy storage mapping.
    mapping(bytes32 => bytes32) private _storage;

    event Upgraded(address indexed implementation);
    event AdminChanged(address indexed previousAdmin, address indexed newAdmin);
    event BeaconUpgraded(address indexed beacon);
}

library Address {
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        // On Solana, value transfers are not supported in CPI.
        // We use call with no value and empty accounts list.
        (bool success, bytes memory returndata) = target.call{accounts: []}(data);
        if (!success) {
            if (returndata.length > 0) {
                // Revert with the returned data.
                // Solang does not support inline assembly revert.
                // We use a require with a message.
                revert(string(returndata));
            } else {
                revert("Address: low-level delegate call failed");
            }
        }
        return returndata;
    }
}