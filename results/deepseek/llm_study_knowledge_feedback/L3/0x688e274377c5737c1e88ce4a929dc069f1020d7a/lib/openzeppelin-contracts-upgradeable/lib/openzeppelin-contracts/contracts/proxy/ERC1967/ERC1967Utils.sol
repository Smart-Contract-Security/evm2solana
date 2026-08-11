// SPDX-License-Identifier: MIT

import {IBeacon} from "../beacon/IBeacon.sol";
import {IERC1967} from "../../interfaces/IERC1967.sol";

library ERC1967Utils {
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function getImplementation() internal view returns (address) {
        return getAddressSlot(IMPLEMENTATION_SLOT).value;
    }

    function _setImplementation(address newImplementation) private {
        getAddressSlot(IMPLEMENTATION_SLOT).value = newImplementation;
    }

    function upgradeToAndCall(address newImplementation, bytes memory data) internal {
        _setImplementation(newImplementation);
        emit IERC1967.Upgraded(newImplementation);

        if (data.length > 0) {
            functionCall(newImplementation, data);
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
        emit IERC1967.AdminChanged(getAdmin(), newAdmin);
        _setAdmin(newAdmin);
    }

    bytes32 internal constant BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    function getBeacon() internal view returns (address) {
        return getAddressSlot(BEACON_SLOT).value;
    }

    function _setBeacon(address newBeacon) private {
        getAddressSlot(BEACON_SLOT).value = newBeacon;

        address beaconImplementation = IBeacon(newBeacon).implementation();
    }

    function upgradeBeaconToAndCall(address newBeacon, bytes memory data) internal {
        _setBeacon(newBeacon);
        emit IERC1967.BeaconUpgraded(newBeacon);

        if (data.length > 0) {
            functionCall(IBeacon(newBeacon).implementation(), data);
        } else {
            _checkNonPayable();
        }
    }

    function _checkNonPayable() private {
    }

    struct AddressSlot {
        address value;
    }

    function getAddressSlot(bytes32 slot) private pure returns (AddressSlot storage r) {
        assembly {
            r.slot := slot
        }
    }

    function functionCall(address target, bytes memory data) private returns (bytes memory) {
        (bool success, bytes memory returndata) = target.call{accounts: []}(data);
        if (!success) {
            if (returndata.length > 0) {
                revert(string(returndata));
            } else {
                revert("Address: low-level call failed");
            }
        }
        return returndata;
    }
}