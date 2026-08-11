// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

library ERC1967Utils {
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    error ERC1967InvalidImplementation(address implementation);
    error ERC1967InvalidAdmin(address admin);
    error ERC1967InvalidBeacon(address beacon);
    error ERC1967NonPayable();

    function getImplementation() internal view returns (address) {
        return getAddressSlot(IMPLEMENTATION_SLOT);
    }

    function _setImplementation(address newImplementation) private {
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
        return getAddressSlot(BEACON_SLOT);
    }

    function _setBeacon(address newBeacon) private {
        setAddressSlot(BEACON_SLOT, newBeacon);
    }

    function upgradeBeaconToAndCall(address newBeacon, bytes memory data) internal {
        _setBeacon(newBeacon);
        emit BeaconUpgraded(newBeacon);

        if (data.length > 0) {
            functionDelegateCall(newBeacon, data);
        } else {
            _checkNonPayable();
        }
    }

    function _checkNonPayable() private {
        if (msg.value > 0) {
            revert("ERC1967: non-payable");
        }
    }

    // --- Solana storage helpers ---

    function getAddressSlot(bytes32 slot) private view returns (address) {
        bytes32 data = getStorage(slot);
        return address(uint160(uint256(data)));
    }

    function setAddressSlot(bytes32 slot, address value) private {
        setStorage(slot, bytes32(uint256(uint160(value))));
    }

    function getStorage(bytes32 slot) private view returns (bytes32 data) {
        assembly {
            data := sload(slot)
        }
    }

    function setStorage(bytes32 slot, bytes32 value) private {
        assembly {
            sstore(slot, value)
        }
    }

    function functionDelegateCall(address target, bytes memory data) private {
        (bool success, ) = target.call{value: 0}(data);
        if (!success) {
            revert("delegate call failed");
        }
    }

    // --- Events ---

    event Upgraded(address indexed implementation);
    event AdminChanged(address previousAdmin, address newAdmin);
    event BeaconUpgraded(address indexed beacon);
}