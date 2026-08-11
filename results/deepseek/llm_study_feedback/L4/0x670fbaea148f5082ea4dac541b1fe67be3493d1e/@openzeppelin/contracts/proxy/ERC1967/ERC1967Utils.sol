// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

// IBeacon interface definition (since import is not available)
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

    // On Solana, we use account data to store persistent values.
    // We store the implementation address at a fixed offset in the contract's data.
    // The slot is used as a key to derive the offset.
    function getImplementation() internal view returns (address) {
        bytes32 slot = IMPLEMENTATION_SLOT;
        address impl;
        // Use inline assembly to read from account data at the derived offset.
        assembly {
            let offset := add(0x100, slot)
            impl := sload(offset)
        }
        return impl;
    }

    function _setImplementation(address newImplementation) private {
        bytes32 slot = IMPLEMENTATION_SLOT;
        assembly {
            let offset := add(0x100, slot)
            sstore(offset, newImplementation)
        }
    }

    function upgradeToAndCall(address newImplementation, bytes memory data) internal {
        _setImplementation(newImplementation);
        emit Upgraded(newImplementation);

        if (data.length > 0) {
            bool success;
            assembly {
                // Use call with all gas instead of delegatecall.
                // delegatecall is not available on Solana via Solang.
                // We pass the data as calldata to the new implementation.
                success := call(gas(), newImplementation, 0, add(data, 0x20), mload(data), 0, 0)
            }
            if (!success) {
                revert("delegatecall failed");
            }
        } else {
            _checkNonPayable();
        }
    }

    bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    function getAdmin() internal view returns (address) {
        bytes32 slot = ADMIN_SLOT;
        address admin;
        assembly {
            let offset := add(0x100, slot)
            admin := sload(offset)
        }
        return admin;
    }

    function _setAdmin(address newAdmin) private {
        if (newAdmin == address(0)) {
            revert("ERC1967: invalid admin");
        }
        bytes32 slot = ADMIN_SLOT;
        assembly {
            let offset := add(0x100, slot)
            sstore(offset, newAdmin)
        }
    }

    function changeAdmin(address newAdmin) internal {
        address previousAdmin = getAdmin();
        emit AdminChanged(previousAdmin, newAdmin);
        _setAdmin(newAdmin);
    }

    bytes32 internal constant BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    function getBeacon() internal view returns (address) {
        bytes32 slot = BEACON_SLOT;
        address beacon;
        assembly {
            let offset := add(0x100, slot)
            beacon := sload(offset)
        }
        return beacon;
    }

    function _setBeacon(address newBeacon) private {
        bytes32 slot = BEACON_SLOT;
        assembly {
            let offset := add(0x100, slot)
            sstore(offset, newBeacon)
        }

        address beaconImplementation = IBeacon(newBeacon).implementation();
    }

    function upgradeBeaconToAndCall(address newBeacon, bytes memory data) internal {
        _setBeacon(newBeacon);
        emit BeaconUpgraded(newBeacon);

        if (data.length > 0) {
            address impl = IBeacon(newBeacon).implementation();
            bool success;
            assembly {
                success := call(gas(), impl, 0, add(data, 0x20), mload(data), 0, 0)
            }
            if (!success) {
                revert("delegatecall failed");
            }
        } else {
            _checkNonPayable();
        }
    }

    function _checkNonPayable() private {
        // On Solana, msg.value is not supported in the same way.
        // We assume the caller ensures no value is sent.
    }
}