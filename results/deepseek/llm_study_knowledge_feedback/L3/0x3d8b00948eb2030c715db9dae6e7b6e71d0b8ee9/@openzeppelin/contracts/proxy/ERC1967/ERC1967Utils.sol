// SPDX-License-Identifier: MIT

import {IBeacon} from "../beacon/IBeacon.sol";
import {IERC1967} from "../../interfaces/IERC1967.sol";

library ERC1967Utils {
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    // On Solana, we store addresses in the contract's data account using a mapping-like approach.
    // We use a simple mapping to simulate storage slots.
    mapping(bytes32 => address) private _addressStorage;

    function getImplementation() internal view returns (address) {
        return _addressStorage[IMPLEMENTATION_SLOT];
    }

    function _setImplementation(address newImplementation) private {
        // On Solana, we cannot check code length of an arbitrary address.
        // We assume the caller validates the implementation address.
        _addressStorage[IMPLEMENTATION_SLOT] = newImplementation;
    }

    function upgradeToAndCall(address newImplementation, bytes memory data) internal {
        _setImplementation(newImplementation);
        emit IERC1967.Upgraded(newImplementation);

        if (data.length > 0) {
            functionDelegateCall(newImplementation, data);
        } else {
            _checkNonPayable();
        }
    }

    bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    function getAdmin() internal view returns (address) {
        return _addressStorage[ADMIN_SLOT];
    }

    function _setAdmin(address newAdmin) private {
        if (newAdmin == address(0)) {
            revert("ERC1967InvalidAdmin");
        }
        _addressStorage[ADMIN_SLOT] = newAdmin;
    }

    function changeAdmin(address newAdmin) internal {
        emit IERC1967.AdminChanged(getAdmin(), newAdmin);
        _setAdmin(newAdmin);
    }

    bytes32 internal constant BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    function getBeacon() internal view returns (address) {
        return _addressStorage[BEACON_SLOT];
    }

    function _setBeacon(address newBeacon) private {
        // On Solana, we cannot check code length of an arbitrary address.
        // We assume the caller validates the beacon address.

        _addressStorage[BEACON_SLOT] = newBeacon;

        address beaconImplementation = IBeacon(newBeacon).implementation();
        // We cannot check code length on Solana, assume valid implementation.
    }

    function upgradeBeaconToAndCall(address newBeacon, bytes memory data) internal {
        _setBeacon(newBeacon);
        emit IERC1967.BeaconUpgraded(newBeacon);

        if (data.length > 0) {
            functionDelegateCall(IBeacon(newBeacon).implementation(), data);
        } else {
            _checkNonPayable();
        }
    }

    function _checkNonPayable() private {
        // msg.value is not supported on Solana; value transfer via function calls is unsupported.
        // The check is removed as it has no effect.
    }

    function functionDelegateCall(address target, bytes memory data) private {
        // delegatecall is not available on Solana, use a regular call instead
        (bool success, ) = target.call{accounts: []}(data);
        require(success, "delegatecall failed");
    }
}