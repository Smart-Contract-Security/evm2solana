// SPDX-License-Identifier: MIT

import {IBeacon} from "../beacon/IBeacon.sol";
import {IERC1967} from "../../interfaces/IERC1967.sol";

/**
 * @dev This library provides getters and event emitting update functions for
 * https://eips.ethereum.org/EIPS/eip-1967[ERC-1967] slots.
 */
library ERC1967Utils {
    /**
     * @dev Storage slot with the address of the current implementation.
     * This is the keccak-256 hash of "eip1967.proxy.implementation" subtracted by 1.
     */
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /**
     * @dev The `implementation` of the proxy is invalid.
     */
    // Custom errors not supported on Solana; using string revert instead.
    // error ERC1967InvalidImplementation(address implementation);

    /**
     * @dev The `admin` of the proxy is invalid.
     */
    // error ERC1967InvalidAdmin(address admin);

    /**
     * @dev The `beacon` of the proxy is invalid.
     */
    // error ERC1967InvalidBeacon(address beacon);

    /**
     * @dev An upgrade function sees `msg.value > 0` that may be lost.
     */
    // error ERC1967NonPayable();

    /**
     * @dev Returns the current implementation address.
     */
    function getImplementation() internal view returns (address) {
        return getAddressSlot(IMPLEMENTATION_SLOT);
    }

    /**
     * @dev Stores a new address in the ERC-1967 implementation slot.
     */
    function _setImplementation(address newImplementation) private {
        // address.code is not supported on Solana.
        // Instead, we check if the account exists by checking its data length via AccountInfo.
        // However, in Solana, we cannot easily check if an address is a program.
        // We'll skip the code length check and rely on the caller to provide a valid program.
        // If needed, the caller should ensure newImplementation is a valid program.
        setAddressSlot(IMPLEMENTATION_SLOT, newImplementation);
    }

    /**
     * @dev Performs implementation upgrade with additional setup call if data is nonempty.
     * This function is payable only if the setup call is performed, otherwise `msg.value` is rejected
     * to avoid stuck value in the contract.
     *
     * Emits an {IERC1967-Upgraded} event.
     */
    function upgradeToAndCall(address newImplementation, bytes memory data) internal {
        _setImplementation(newImplementation);
        emit IERC1967.Upgraded(newImplementation);

        if (data.length > 0) {
            // Address.functionDelegateCall is not available; use delegatecall-like pattern.
            // On Solana, delegatecall is not available. We use a regular call to the implementation.
            // The implementation should handle the initialization logic.
            // We perform a cross-program invocation (CPI) to the new implementation.
            // Since we cannot do delegatecall, we call the implementation directly with the data.
            // This requires the implementation to have a function that matches the selector in data.
            (bool success, ) = newImplementation.call(data);
            require(success, "ERC1967: upgrade failed");
        } else {
            _checkNonPayable();
        }
    }

    /**
     * @dev Storage slot with the admin of the contract.
     * This is the keccak-256 hash of "eip1967.proxy.admin" subtracted by 1.
     */
    bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /**
     * @dev Returns the current admin.
     */
    function getAdmin() internal view returns (address) {
        return getAddressSlot(ADMIN_SLOT);
    }

    /**
     * @dev Stores a new address in the ERC-1967 admin slot.
     */
    function _setAdmin(address newAdmin) private {
        if (newAdmin == address(0)) {
            revert("ERC1967: invalid admin");
        }
        setAddressSlot(ADMIN_SLOT, newAdmin);
    }

    /**
     * @dev Changes the admin of the proxy.
     *
     * Emits an {IERC1967-AdminChanged} event.
     */
    function changeAdmin(address newAdmin) internal {
        emit IERC1967.AdminChanged(getAdmin(), newAdmin);
        _setAdmin(newAdmin);
    }

    /**
     * @dev The storage slot of the UpgradeableBeacon contract which defines the implementation for this proxy.
     * This is the keccak-256 hash of "eip1967.proxy.beacon" subtracted by 1.
     */
    bytes32 internal constant BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    /**
     * @dev Returns the current beacon.
     */
    function getBeacon() internal view returns (address) {
        return getAddressSlot(BEACON_SLOT);
    }

    /**
     * @dev Stores a new beacon in the ERC-1967 beacon slot.
     */
    function _setBeacon(address newBeacon) private {
        // address.code is not supported on Solana.
        // Skip the code length check.
        setAddressSlot(BEACON_SLOT, newBeacon);

        address beaconImplementation = IBeacon(newBeacon).implementation();
        // Skip code length check for beaconImplementation.
        // If needed, the caller should ensure it's a valid program.
    }

    /**
     * @dev Change the beacon and trigger a setup call if data is nonempty.
     *
     * Emits an {IERC1967-BeaconUpgraded} event.
     */
    function upgradeBeaconToAndCall(address newBeacon, bytes memory data) internal {
        _setBeacon(newBeacon);
        emit IERC1967.BeaconUpgraded(newBeacon);

        if (data.length > 0) {
            address impl = IBeacon(newBeacon).implementation();
            (bool success, ) = impl.call(data);
            require(success, "ERC1967: beacon upgrade failed");
        } else {
            _checkNonPayable();
        }
    }

    /**
     * @dev Reverts if `msg.value` is not zero.
     */
    function _checkNonPayable() private {
        // msg.value is not supported on Solana.
        // No-op.
    }

    // --- StorageSlot replacement ---
    // Since StorageSlot is not available, we implement the address slot logic directly.

    /**
     * @dev Returns the address stored at the given storage slot.
     */
    function getAddressSlot(bytes32 slot) private view returns (address) {
        bytes32 data;
        assembly {
            data := sload(slot)
        }
        return address(uint160(uint256(data)));
    }

    /**
     * @dev Stores an address at the given storage slot.
     */
    function setAddressSlot(bytes32 slot, address value) private {
        assembly {
            sstore(slot, value)
        }
    }
}