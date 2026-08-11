// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

library ERC1967Utils {
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    error ERC1967InvalidImplementation(address implementation);
    error ERC1967InvalidAdmin(address admin);
    error ERC1967InvalidBeacon(address beacon);
    error ERC1967NonPayable();

    function getImplementation() internal view returns (address) {
        return getAddressSlot(IMPLEMENTATION_SLOT).value;
    }

    function _setImplementation(address newImplementation) private {
        // On Solana, we cannot check code length. We assume the implementation is valid.
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

    bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    function getAdmin() internal view returns (address) {
        return getAddressSlot(ADMIN_SLOT).value;
    }

    function _setAdmin(address newAdmin) private {
        if (newAdmin == address(0)) {
            revert("ERC1967: invalid admin (address(0))");
        }
        getAddressSlot(ADMIN_SLOT).value = newAdmin;
    }

    function changeAdmin(address newAdmin) internal {
        emit AdminChanged(getAdmin(), newAdmin);
        _setAdmin(newAdmin);
    }

    bytes32 internal constant BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    function getBeacon() internal view returns (address) {
        return getAddressSlot(BEACON_SLOT).value;
    }

    function _setBeacon(address newBeacon) private {
        // On Solana, we cannot check code length. We assume the beacon is valid.
        getAddressSlot(BEACON_SLOT).value = newBeacon;

        // IBeacon interface call replaced with low-level call
        (bool success, bytes memory ret) = newBeacon.call{accounts: []}(abi.encodeWithSignature("implementation()"));
        require(success, "ERC1967: beacon implementation call failed");
        address beaconImplementation = abi.decode(ret, (address));
        // Assume implementation is valid
    }

    function upgradeBeaconToAndCall(address newBeacon, bytes memory data) internal {
        _setBeacon(newBeacon);
        emit BeaconUpgraded(newBeacon);

        if (data.length > 0) {
            (bool success, bytes memory ret) = newBeacon.call{accounts: []}(abi.encodeWithSignature("implementation()"));
            require(success, "ERC1967: beacon implementation call failed");
            address impl = abi.decode(ret, (address));
            functionDelegateCall(impl, data);
        } else {
            _checkNonPayable();
        }
    }

    function _checkNonPayable() private {
        if (msg.value > 0) {
            revert("ERC1967: non-payable");
        }
    }

    // Inline StorageSlot replacement
    struct AddressSlot {
        address value;
    }

    function getAddressSlot(bytes32 slot) private pure returns (AddressSlot storage r) {
        assembly {
            r.slot := slot
        }
    }

    // Inline Address.functionDelegateCall replacement using CPI
    function functionDelegateCall(address target, bytes memory data) private {
        // On Solana, delegatecall is not available. We use a regular call as a fallback.
        (bool success, bytes memory returndata) = target.call{accounts: []}(data);
        if (!success) {
            if (returndata.length > 0) {
                assembly {
                    revert(add(returndata, 32), mload(returndata))
                }
            } else {
                revert("Address: low-level delegate call failed");
            }
        }
    }

    // Events (replacing IERC1967 interface events)
    event Upgraded(address indexed implementation);
    event AdminChanged(address previousAdmin, address newAdmin);
    event BeaconUpgraded(address indexed beacon);
}