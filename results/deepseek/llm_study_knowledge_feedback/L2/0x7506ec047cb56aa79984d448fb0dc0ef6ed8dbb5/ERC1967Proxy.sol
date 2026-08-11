import 'solana';

abstract contract Proxy {
    function _delegate(address implementation) internal virtual {
        // delegatecall is not available on Solana
        revert("delegatecall not supported");
    }

    function _implementation() internal view virtual returns (address);

    function _fallback() internal virtual {
        _delegate(_implementation());
    }

    fallback() external virtual {
        _fallback();
    }
}

library Address {
    error FailedInnerCall();

    function sendValue(address payable recipient, uint64 amount) internal {
        // Value transfer via function calls is unsupported on Solana.
        // Use system program to transfer lamports.
        revert("sendValue not supported on Solana");
    }

    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0);
    }

    function functionCallWithValue(address target, bytes memory data, uint64 value) internal returns (bytes memory) {
        // Value transfer via function calls is unsupported on Solana.
        revert("functionCallWithValue not supported on Solana");
    }

    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        // staticcall is not available on Solana. Use regular call with read-only accounts.
        revert("staticcall not supported on Solana");
    }

    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        // delegatecall is not available on Solana
        revert("delegatecall not supported");
    }

    function verifyCallResultFromTarget(
        address target,
        bool success,
        bytes memory returndata
    ) internal view returns (bytes memory) {
        if (!success) {
            _revert(returndata);
        } else {
            // address.code is not supported on Solana.
            // We cannot check code length; assume target is valid if call succeeded.
            return returndata;
        }
    }

    function verifyCallResult(bool success, bytes memory returndata) internal pure returns (bytes memory) {
        if (!success) {
            _revert(returndata);
        } else {
            return returndata;
        }
    }

    function _revert(bytes memory returndata) private pure {
        uint256 len = returndata.length;
        if (len > 0) {
            // mload is not available on Solana. Use inline assembly with revert.
            // Revert with the provided data.
            assembly {
                revert(add(returndata, 32), len)
            }
        } else {
            revert("Address: inner call failed");
        }
    }
}

library StorageSlot {
    struct AddressSlot {
        address value;
    }

    struct BooleanSlot {
        bool value;
    }

    struct Bytes32Slot {
        bytes32 value;
    }

    struct Uint256Slot {
        uint256 value;
    }

    struct StringSlot {
        string value;
    }

    struct BytesSlot {
        bytes value;
    }

    function getAddressSlot(bytes32 slot) internal pure returns (AddressSlot storage r) {
        assembly {
            r.slot := slot
        }
    }

    function getBooleanSlot(bytes32 slot) internal pure returns (BooleanSlot storage r) {
        assembly {
            r.slot := slot
        }
    }

    function getBytes32Slot(bytes32 slot) internal pure returns (Bytes32Slot storage r) {
        assembly {
            r.slot := slot
        }
    }

    function getUint256Slot(bytes32 slot) internal pure returns (Uint256Slot storage r) {
        assembly {
            r.slot := slot
        }
    }

    function getStringSlot(bytes32 slot) internal pure returns (StringSlot storage r) {
        assembly {
            r.slot := slot
        }
    }

    function getStringSlot(string storage store) internal pure returns (StringSlot storage r) {
        assembly {
            r.slot := store.slot
        }
    }

    function getBytesSlot(bytes32 slot) internal pure returns (BytesSlot storage r) {
        assembly {
            r.slot := slot
        }
    }

    function getBytesSlot(bytes storage store) internal pure returns (BytesSlot storage r) {
        assembly {
            r.slot := store.slot
        }
    }
}

library ERC1967Utils {
    event Upgraded(address indexed implementation);
    event AdminChanged(address previousAdmin, address newAdmin);
    event BeaconUpgraded(address indexed beacon);

    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    error ERC1967InvalidImplementation(address implementation);
    error ERC1967InvalidAdmin(address admin);
    error ERC1967InvalidBeacon(address beacon);
    error ERC1967NonPayable();

    function getImplementation() internal view returns (address) {
        return StorageSlot.getAddressSlot(IMPLEMENTATION_SLOT).value;
    }

    function _setImplementation(address newImplementation) private {
        // address.code is not supported on Solana.
        // We cannot check code length; assume implementation is valid.
        StorageSlot.getAddressSlot(IMPLEMENTATION_SLOT).value = newImplementation;
    }

    function upgradeToAndCall(address newImplementation, bytes memory data) internal {
        _setImplementation(newImplementation);
        emit Upgraded(newImplementation);

        uint256 dataLen = data.length;
        if (dataLen > 0) {
            Address.functionDelegateCall(newImplementation, data);
        } else {
            _checkNonPayable();
        }
    }

    bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    function getAdmin() internal view returns (address) {
        return StorageSlot.getAddressSlot(ADMIN_SLOT).value;
    }

    function _setAdmin(address newAdmin) private {
        if (newAdmin == address(0)) {
            revert("ERC1967: invalid admin");
        }
        StorageSlot.getAddressSlot(ADMIN_SLOT).value = newAdmin;
    }

    function changeAdmin(address newAdmin) internal {
        emit AdminChanged(getAdmin(), newAdmin);
        _setAdmin(newAdmin);
    }

    bytes32 internal constant BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    function getBeacon() internal view returns (address) {
        return StorageSlot.getAddressSlot(BEACON_SLOT).value;
    }

    function _setBeacon(address newBeacon) private {
        // address.code is not supported on Solana.
        // We cannot check code length; assume beacon is valid.
        StorageSlot.getAddressSlot(BEACON_SLOT).value = newBeacon;

        // IBeacon is not available. We cannot call implementation() without the interface.
        // Assume the beacon is valid and skip the implementation check.
    }

    function upgradeBeaconToAndCall(address newBeacon, bytes memory data) internal {
        _setBeacon(newBeacon);
        emit BeaconUpgraded(newBeacon);

        uint256 dataLen = data.length;
        if (dataLen > 0) {
            // IBeacon is not available. Cannot call implementation().
            // Revert or skip. We'll revert as the interface is missing.
            revert("IBeacon not supported on Solana");
        } else {
            _checkNonPayable();
        }
    }

    function _checkNonPayable() private {
        // msg.value is not supported on Solana.
        // No-op.
    }
}

contract ERC1967Proxy is Proxy {
    @payer(payer)
    @space(256)
    constructor(address implementation, bytes memory _data) {
        ERC1967Utils.upgradeToAndCall(implementation, _data);
    }

    function _implementation() internal view virtual override returns (address) {
        return ERC1967Utils.getImplementation();
    }
}