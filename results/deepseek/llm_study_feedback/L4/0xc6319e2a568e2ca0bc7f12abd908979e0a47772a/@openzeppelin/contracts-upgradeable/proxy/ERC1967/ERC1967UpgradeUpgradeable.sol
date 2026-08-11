// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "../../interfaces/IERC1967Upgradeable.sol";
import "../../interfaces/draft-IERC1822Upgradeable.sol";
import "../../utils/AddressUpgradeable.sol";
import "../../utils/StorageSlotUpgradeable.sol";

abstract contract ERC1967UpgradeUpgradeable is IERC1967Upgradeable {
    bytes32 private constant _ROLLBACK_SLOT = 0x4910fdfa16fed3260ed0e7147f7cc6da11a60208b5b9406d12a635614ffd9143;

    bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function __ERC1967Upgrade_init() internal {
    }

    function __ERC1967Upgrade_init_unchained() internal {
    }

    function _getImplementation() internal view returns (address) {
        return StorageSlotUpgradeable.getAddressSlot(_IMPLEMENTATION_SLOT).value;
    }

    function _setImplementation(address newImplementation) private {
        require(AddressUpgradeable.isContract(newImplementation), "ERC1967: new implementation is not a contract");
        StorageSlotUpgradeable.getAddressSlot(_IMPLEMENTATION_SLOT).value = newImplementation;
    }

    function _upgradeTo(address newImplementation) internal {
        _setImplementation(newImplementation);
        emit Upgraded(newImplementation);
    }

    function _upgradeToAndCall(address newImplementation, bytes memory data, bool forceCall) internal {
        _upgradeTo(newImplementation);
        if (data.length > 0 || forceCall) {
            AddressUpgradeable.functionDelegateCall(newImplementation, data);
        }
    }

    function _upgradeToAndCallUUPS(address newImplementation, bytes memory data, bool forceCall) internal {
        if (StorageSlotUpgradeable.getBooleanSlot(_ROLLBACK_SLOT).value) {
            _setImplementation(newImplementation);
        } else {
            // Solang does not support try/catch. We call proxiableUUID directly and check the return value.
            // If the call fails, the entire transaction will revert, which is acceptable for UUPS validation.
            bytes32 slot = IERC1822ProxiableUpgradeable(newImplementation).proxiableUUID{accounts: [newImplementation]}();
            require(slot == _IMPLEMENTATION_SLOT, "ERC1967Upgrade: unsupported proxiableUUID");
            _upgradeToAndCall(newImplementation, data, forceCall);
        }
    }

    bytes32 internal constant _ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    function _getAdmin() internal view returns (address) {
        return StorageSlotUpgradeable.getAddressSlot(_ADMIN_SLOT).value;
    }

    function _setAdmin(address newAdmin) private {
        require(newAdmin != address(0), "ERC1967: new admin is the zero address");
        StorageSlotUpgradeable.getAddressSlot(_ADMIN_SLOT).value = newAdmin;
    }

    function _changeAdmin(address newAdmin) internal {
        emit AdminChanged(_getAdmin(), newAdmin);
        _setAdmin(newAdmin);
    }

    bytes32 internal constant _BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    function _getBeacon() internal view returns (address) {
        return StorageSlotUpgradeable.getAddressSlot(_BEACON_SLOT).value;
    }

    function _setBeacon(address newBeacon) private {
        require(AddressUpgradeable.isContract(newBeacon), "ERC1967: new beacon is not a contract");
        // IBeaconUpgradeable is not available; we assume the beacon contract has an implementation() function.
        // We call it via a low-level call to avoid importing the missing interface.
        (bool success, bytes memory returndata) = newBeacon.call{accounts: [newBeacon]}(abi.encodeWithSignature("implementation()"));
        require(success, "ERC1967: beacon implementation call failed");
        address beaconImpl = abi.decode(returndata, (address));
        require(AddressUpgradeable.isContract(beaconImpl), "ERC1967: beacon implementation is not a contract");
        StorageSlotUpgradeable.getAddressSlot(_BEACON_SLOT).value = newBeacon;
    }

    function _upgradeBeaconToAndCall(address newBeacon, bytes memory data, bool forceCall) internal {
        _setBeacon(newBeacon);
        emit BeaconUpgraded(newBeacon);
        if (data.length > 0 || forceCall) {
            // Retrieve the implementation address from the beacon
            (bool success, bytes memory returndata) = newBeacon.call{accounts: [newBeacon]}(abi.encodeWithSignature("implementation()"));
            require(success, "ERC1967: beacon implementation call failed");
            address beaconImpl = abi.decode(returndata, (address));
            AddressUpgradeable.functionDelegateCall(beaconImpl, data);
        }
    }

    uint256[50] private __gap;
}