// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

interface IBeacon {
    function implementation() external view returns (address);
}

library ERC1967Utils {
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    error ERC1967InvalidImplementation(address implementation);
    error ERC1967InvalidAdmin(address admin);
    error ERC1967InvalidBeacon(address beacon);
    error ERC1967NonPayable();

    event Upgraded(address indexed implementation);
    event AdminChanged(address indexed previousAdmin, address indexed newAdmin);
    event BeaconUpgraded(address indexed beacon);

    function getImplementation() internal view returns (address) {
        return getAddressSlot(IMPLEMENTATION_SLOT);
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
            functionDelegateCall(newImplementation, data);
        } else {
            _checkNonPayable();
        }
    }

    bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    function getAdmin() internal view returns (address) {
        return getAddressSlot(ADMIN_SLOT);
    }

    function _setAdmin(address newAdmin) private {
        if (newAdmin == address(0)) {
            revert ERC1967InvalidAdmin(address(0));
        }
        setAddressSlot(ADMIN_SLOT, newAdmin);
    }

    function changeAdmin(address newAdmin) internal {
        emit AdminChanged(getAdmin(), newAdmin);
        _setAdmin(newAdmin);
    }

    bytes32 internal constant BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    function getBeacon() internal view returns (address) {
        return getAddressSlot(BEACON_SLOT);
    }

    function _setBeacon(address newBeacon) private {
        // On Solana, we cannot check code length of an arbitrary address.
        // We assume the caller has validated the beacon.
        setAddressSlot(BEACON_SLOT, newBeacon);

        address beaconImplementation = IBeacon(newBeacon).implementation();
        // On Solana, we cannot check code length of an arbitrary address.
        // We assume the beacon implementation is valid.
    }

    function upgradeBeaconToAndCall(address newBeacon, bytes memory data) internal {
        _setBeacon(newBeacon);
        emit BeaconUpgraded(newBeacon);

        if (data.length > 0) {
            functionDelegateCall(IBeacon(newBeacon).implementation(), data);
        } else {
            _checkNonPayable();
        }
    }

    function _checkNonPayable() private {
        if (msg.value > 0) {
            revert ERC1967NonPayable();
        }
    }

    function getAddressSlot(bytes32 slot) private view returns (address) {
        bytes32 data = getStorage(slot);
        return address(uint160(uint256(data)));
    }

    function setAddressSlot(bytes32 slot, address value) private {
        setStorage(slot, bytes32(uint256(uint160(value))));
    }

    function getStorage(bytes32 slot) private view returns (bytes32 data) {
        // On Solana, we use account data storage instead of sload.
        // The slot is used as a key to a mapping stored in the account data.
        // This is a simplified approach; a real implementation would use a proper storage layout.
        bytes32 key = keccak256(abi.encode(slot));
        // We cannot directly read from storage without assembly.
        // Instead, we use a state variable mapping approach.
        // Since this is a library, we rely on the caller's storage.
        // For simplicity, we assume the storage is managed externally.
        // In a real port, you would use a mapping(bytes32 => bytes32) in the contract.
        // Here we just return 0 as a placeholder.
        data = bytes32(0);
    }

    function setStorage(bytes32 slot, bytes32 value) private {
        // On Solana, we use account data storage instead of sstore.
        // The slot is used as a key to a mapping stored in the account data.
        // This is a simplified approach; a real implementation would use a proper storage layout.
        bytes32 key = keccak256(abi.encode(slot));
        // We cannot directly write to storage without assembly.
        // Instead, we use a state variable mapping approach.
        // Since this is a library, we rely on the caller's storage.
        // For simplicity, we assume the storage is managed externally.
        // In a real port, you would use a mapping(bytes32 => bytes32) in the contract.
        // Here we do nothing as a placeholder.
    }

    function functionDelegateCall(address target, bytes memory data) private {
        // On Solana, we cannot transfer native value via CPI.
        // We use a call without value transfer.
        (bool success, bytes memory returndata) = target.call{accounts: [target]}(data);
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