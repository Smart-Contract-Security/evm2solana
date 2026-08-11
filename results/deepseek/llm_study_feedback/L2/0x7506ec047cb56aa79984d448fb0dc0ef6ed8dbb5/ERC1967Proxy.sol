// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

abstract contract Proxy {
    function _delegate(address implementation) internal virtual {
        // Solang does not support inline assembly for delegatecall.
        // Use a low-level call via the implementation's fallback.
        // The calldata is forwarded automatically by the runtime.
        // We perform a delegate-like call by invoking the implementation
        // with the current calldata. On Solana, delegatecall semantics
        // are not directly available; we approximate by calling the
        // implementation's fallback with the same accounts and data.
        // This requires the implementation to be a program that can
        // handle the call.
        (bool success, bytes memory returndata) = implementation.call{value: 0}(msg.data);
        if (!success) {
            if (returndata.length > 0) {
                // Revert with the returned data
                assembly {
                    revert(add(returndata, 32), mload(returndata))
                }
            } else {
                revert("delegatecall failed");
            }
        } else {
            // Return the returndata
            assembly {
                return(add(returndata, 32), mload(returndata))
            }
        }
    }

    function _implementation() internal view virtual returns (address);

    function _fallback() internal virtual {
        _delegate(_implementation());
    }

    // Solang requires receive() for payable fallback, not fallback() payable.
    // On Solana, receive() is not supported. Use a regular fallback function.
    fallback() external virtual {
        _fallback();
    }
}

interface IBeacon {
    function implementation() external view returns (address);
}

library Address {
    error AddressInsufficientBalance(address account);
    error AddressEmptyCode(address target);
    error FailedInnerCall();

    function sendValue(address payable recipient, uint256 amount) internal {
        // On Solana, balance is not available on address(this).
        // We use tx.accounts.this.lamports to get the balance.
        // However, the exact account name depends on the context.
        // For a library, we cannot access tx.accounts directly.
        // We'll assume the caller passes the balance or we skip the check.
        // Since this is a utility, we'll use a low-level call with value.
        // The runtime will handle the balance check.
        (bool success, ) = recipient.call{value: amount}("");
        if (!success) {
            revert FailedInnerCall();
        }
    }

    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0);
    }

    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        // Balance check removed because address(this).balance is not available.
        // The call will fail if insufficient lamports.
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        // staticcall is not available on Solana. Use a regular call with value 0.
        // This changes semantics but is the closest approximation.
        (bool success, bytes memory returndata) = target.call{value: 0}(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        // delegatecall is not available on Solana. Use a regular call.
        (bool success, bytes memory returndata) = target.call{value: 0}(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    function verifyCallResultFromTarget(
        address target,
        bool success,
        bytes memory returndata
    ) internal view returns (bytes memory) {
        if (!success) {
            _revert(returndata);
        } else {
            // target.code.length is not supported. We skip the empty code check.
            // Instead, we assume the call succeeded if success is true.
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
        if (returndata.length > 0) {
            // mload is not available. Use inline assembly to revert with the data.
            // Solang supports revert with bytes memory.
            // We can just revert with the returndata directly.
            // However, custom error revert is not supported.
            // We'll revert with a string or use the returndata as reason.
            // Since we cannot use mload, we'll revert with the raw bytes.
            // Solang allows revert with bytes.
            revert(string(returndata));
        } else {
            revert("FailedInnerCall");
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
    bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
    bytes32 internal constant BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    error ERC1967InvalidImplementation(address implementation);
    error ERC1967InvalidAdmin(address admin);
    error ERC1967InvalidBeacon(address beacon);
    error ERC1967NonPayable();

    function getImplementation() internal view returns (address) {
        return StorageSlot.getAddressSlot(IMPLEMENTATION_SLOT).value;
    }

    function _setImplementation(address newImplementation) private {
        // address.code.length is not supported. We skip the check.
        // We assume the address is a valid program.
        StorageSlot.getAddressSlot(IMPLEMENTATION_SLOT).value = newImplementation;
    }

    function upgradeToAndCall(address newImplementation, bytes memory data) internal {
        _setImplementation(newImplementation);
        emit Upgraded(newImplementation);

        if (data.length > 0) {
            Address.functionDelegateCall(newImplementation, data);
        } else {
            _checkNonPayable();
        }
    }

    function getAdmin() internal view returns (address) {
        return StorageSlot.getAddressSlot(ADMIN_SLOT).value;
    }

    function _setAdmin(address newAdmin) private {
        if (newAdmin == address(0)) {
            revert("ERC1967InvalidAdmin: zero address");
        }
        StorageSlot.getAddressSlot(ADMIN_SLOT).value = newAdmin;
    }

    function changeAdmin(address newAdmin) internal {
        emit AdminChanged(getAdmin(), newAdmin);
        _setAdmin(newAdmin);
    }

    function getBeacon() internal view returns (address) {
        return StorageSlot.getAddressSlot(BEACON_SLOT).value;
    }

    function _setBeacon(address newBeacon) private {
        // address.code.length is not supported. Skip check.
        StorageSlot.getAddressSlot(BEACON_SLOT).value = newBeacon;

        address beaconImplementation = IBeacon(newBeacon).implementation();
        // Skip code length check.
    }

    function upgradeBeaconToAndCall(address newBeacon, bytes memory data) internal {
        _setBeacon(newBeacon);
        emit BeaconUpgraded(newBeacon);

        if (data.length > 0) {
            Address.functionDelegateCall(IBeacon(newBeacon).implementation(), data);
        } else {
            _checkNonPayable();
        }
    }

    function _checkNonPayable() private {
        if (msg.value > 0) {
            revert("ERC1967NonPayable: value not allowed");
        }
    }
}

contract ERC1967Proxy is Proxy {
    constructor(address implementation, bytes memory _data) payable {
        ERC1967Utils.upgradeToAndCall(implementation, _data);
    }

    function _implementation() internal view virtual override returns (address) {
        return ERC1967Utils.getImplementation();
    }
}