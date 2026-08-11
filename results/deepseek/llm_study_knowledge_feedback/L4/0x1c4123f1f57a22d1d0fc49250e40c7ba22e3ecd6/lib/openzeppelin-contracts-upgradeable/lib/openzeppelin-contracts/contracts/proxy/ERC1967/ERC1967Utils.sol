// SPDX-License-Identifier: MIT

interface IBeacon {
    function implementation() external view returns (address);
}

contract ERC1967Utils {
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    event Upgraded(address indexed implementation);
    event AdminChanged(address indexed previousAdmin, address indexed newAdmin);
    event BeaconUpgraded(address indexed beacon);

    address private _implementation;
    address private _admin;
    address private _beacon;

    function getImplementation() internal view returns (address) {
        return _implementation;
    }

    function _setImplementation(address newImplementation) private {
        _implementation = newImplementation;
    }

    function upgradeToAndCall(address newImplementation, bytes memory data) internal {
        _setImplementation(newImplementation);
        emit Upgraded(newImplementation);

        if (data.length > 0) {
            _functionDelegateCall(newImplementation, data);
        } else {
            _checkNonPayable();
        }
    }

    bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    function getAdmin() internal view returns (address) {
        return _admin;
    }

    function _setAdmin(address newAdmin) private {
        _admin = newAdmin;
    }

    function changeAdmin(address newAdmin) internal {
        emit AdminChanged(getAdmin(), newAdmin);
        _setAdmin(newAdmin);
    }

    bytes32 internal constant BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    function getBeacon() internal view returns (address) {
        return _beacon;
    }

    function _setBeacon(address newBeacon) private {
        _beacon = newBeacon;
    }

    function upgradeBeaconToAndCall(address newBeacon, bytes memory data) internal {
        _setBeacon(newBeacon);
        emit BeaconUpgraded(newBeacon);

        if (data.length > 0) {
            _functionDelegateCall(newBeacon, data);
        } else {
            _checkNonPayable();
        }
    }

    function _checkNonPayable() private {
        // msg.value is not supported on Solana; value transfers are not possible via function calls.
    }

    function _functionDelegateCall(address target, bytes memory data) private {
        (bool success, bytes memory returndata) = target.call(data);
        if (!success) {
            if (returndata.length > 0) {
                assembly {
                    revert(add(returndata, 32), mload(returndata))
                }
            } else {
                revert();
            }
        }
    }
}