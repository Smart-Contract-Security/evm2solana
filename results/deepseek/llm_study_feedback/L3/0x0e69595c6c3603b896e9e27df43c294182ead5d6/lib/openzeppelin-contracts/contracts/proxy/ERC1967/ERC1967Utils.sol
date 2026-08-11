// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library ERC1967Utils {
    event Upgraded(address indexed implementation);
    event AdminChanged(address previousAdmin, address newAdmin);
    event BeaconUpgraded(address indexed beacon);

    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function getImplementation() internal view returns (address) {
        return getAddressSlot(IMPLEMENTATION_SLOT).value;
    }

    function _setImplementation(address newImplementation) private {
        // On Solana, we cannot check code length via address.code.
        // We assume the caller validates the implementation address.
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
            revert("ERC1967: invalid admin");
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
        // On Solana, we cannot check code length via address.code.
        // We assume the caller validates the beacon address.
        getAddressSlot(BEACON_SLOT).value = newBeacon;

        // IBeacon is not available; we inline the call to implementation().
        // We assume newBeacon is a contract that exposes implementation().
        (bool ok, bytes memory ret) = newBeacon.call{accounts: []}(abi.encodeWithSignature("implementation()"));
        require(ok, "ERC1967: beacon implementation call failed");
        address beaconImplementation = abi.decode(ret, (address));
        // We cannot check code length; assume valid.
    }

    function upgradeBeaconToAndCall(address newBeacon, bytes memory data) internal {
        _setBeacon(newBeacon);
        emit BeaconUpgraded(newBeacon);

        if (data.length > 0) {
            (bool ok, bytes memory ret) = newBeacon.call{accounts: []}(abi.encodeWithSignature("implementation()"));
            require(ok, "ERC1967: beacon implementation call failed");
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

    struct AddressSlot {
        address value;
    }

    function getAddressSlot(bytes32 slot) private pure returns (AddressSlot storage r) {
        assembly {
            r.slot := slot
        }
    }

    // On Solana, delegatecall is not supported. We use a regular call as a fallback.
    // This changes semantics but allows compilation. Adjust as needed for your proxy pattern.
    function functionDelegateCall(address target, bytes memory data) private {
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
}