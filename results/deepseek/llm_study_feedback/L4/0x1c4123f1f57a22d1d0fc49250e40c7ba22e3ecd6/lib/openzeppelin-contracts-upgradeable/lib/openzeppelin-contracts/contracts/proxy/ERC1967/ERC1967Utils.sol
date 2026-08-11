// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

library ERC1967Utils {
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    event Upgraded(address indexed implementation);
    event AdminChanged(address indexed previousAdmin, address indexed newAdmin);
    event BeaconUpgraded(address indexed beacon);

    function getImplementation() internal view returns (address) {
        return address(uint160(uint256(getAddressSlot(IMPLEMENTATION_SLOT))));
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
        setAddressSlot(BEACON_SLOT, newBeacon);

        (bool success, bytes memory returndata) = newBeacon.call{accounts: [newBeacon]}(
            abi.encodeWithSignature("implementation()")
        );
        if (!success) {
            revert("ERC1967: beacon implementation call failed");
        }
        address beaconImplementation = abi.decode(returndata, (address));
    }

    function upgradeBeaconToAndCall(address newBeacon, bytes memory data) internal {
        _setBeacon(newBeacon);
        emit BeaconUpgraded(newBeacon);

        if (data.length > 0) {
            (bool success, bytes memory returndata) = newBeacon.call{accounts: [newBeacon]}(
                abi.encodeWithSignature("implementation()")
            );
            if (!success) {
                revert("ERC1967: beacon implementation call failed");
            }
            address beaconImplementation = abi.decode(returndata, (address));
            functionDelegateCall(beaconImplementation, data);
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
        bytes32 value;
        assembly {
            let offset := and(slot, 0xFFFFFFFF)
            value := sload(offset)
        }
        return value;
    }

    function setAddressSlot(bytes32 slot, address addr) private {
        assembly {
            let offset := and(slot, 0xFFFFFFFF)
            sstore(offset, addr)
        }
    }

    function functionDelegateCall(address target, bytes memory data) private {
        (bool success, bytes memory returndata) = target.call{accounts: [target]}(data);
        if (!success) {
            if (returndata.length > 0) {
                assembly {
                    revert(add(returndata, 32), mload(returndata))
                }
            } else {
                revert("ERC1967Utils: delegate call failed");
            }
        }
    }
}