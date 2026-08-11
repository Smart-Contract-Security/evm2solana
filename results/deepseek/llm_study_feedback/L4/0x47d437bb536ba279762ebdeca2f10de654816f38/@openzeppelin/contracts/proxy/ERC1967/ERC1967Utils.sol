// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

library ERC1967Utils {
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    error ERC1967InvalidImplementation(address implementation);
    error ERC1967InvalidAdmin(address admin);
    error ERC1967InvalidBeacon(address beacon);
    error ERC1967NonPayable();

    event Upgraded(address indexed implementation);
    event AdminChanged(address indexed previousAdmin, address indexed newAdmin);
    event BeaconUpgraded(address indexed beacon);

    function getImplementation() internal view returns (address) {
        address impl;
        assembly {
            let ptr := solana::account_data()
            impl := mload(ptr)
        }
        return impl;
    }

    function _setImplementation(address newImplementation) private {
        assembly {
            let ptr := solana::account_data()
            mstore(ptr, newImplementation)
        }
    }

    function upgradeToAndCall(address newImplementation, bytes memory data) internal {
        _setImplementation(newImplementation);
        emit Upgraded(newImplementation);

        if (data.length > 0) {
            bool success;
            assembly {
                success := delegatecall(0, newImplementation, add(data, 0x20), mload(data), 0, 0)
            }
            require(success, "ERC1967Utils: delegatecall failed");
        } else {
            _checkNonPayable();
        }
    }

    bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    function getAdmin() internal view returns (address) {
        address admin;
        assembly {
            let ptr := solana::account_data()
            admin := mload(add(ptr, 32))
        }
        return admin;
    }

    function _setAdmin(address newAdmin) private {
        if (newAdmin == address(0)) {
            revert ERC1967InvalidAdmin(address(0));
        }
        assembly {
            let ptr := solana::account_data()
            mstore(add(ptr, 32), newAdmin)
        }
    }

    function changeAdmin(address newAdmin) internal {
        emit AdminChanged(getAdmin(), newAdmin);
        _setAdmin(newAdmin);
    }

    bytes32 internal constant BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    function getBeacon() internal view returns (address) {
        address beacon;
        assembly {
            let ptr := solana::account_data()
            beacon := mload(add(ptr, 64))
        }
        return beacon;
    }

    function _setBeacon(address newBeacon) private {
        assembly {
            let ptr := solana::account_data()
            mstore(add(ptr, 64), newBeacon)
        }

        (bool success, bytes memory returndata) = newBeacon.staticcall(abi.encodeWithSignature("implementation()"));
        require(success, "ERC1967Utils: beacon implementation call failed");
    }

    function upgradeBeaconToAndCall(address newBeacon, bytes memory data) internal {
        _setBeacon(newBeacon);
        emit BeaconUpgraded(newBeacon);

        if (data.length > 0) {
            (bool successImpl, bytes memory implData) = newBeacon.staticcall(abi.encodeWithSignature("implementation()"));
            require(successImpl, "ERC1967Utils: beacon implementation call failed");
            address impl = abi.decode(implData, (address));

            bool success;
            assembly {
                success := delegatecall(0, impl, add(data, 0x20), mload(data), 0, 0)
            }
            require(success, "ERC1967Utils: delegatecall failed");
        } else {
            _checkNonPayable();
        }
    }

    function _checkNonPayable() private {
        // On Solana, msg.value is not supported in the same way.
        // We cannot check for native value transfer via CPI.
        // This check is omitted for Solana compatibility.
    }
}