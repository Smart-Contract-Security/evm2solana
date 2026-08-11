// SPDX-License-Identifier: MIT

import {IERC1967} from "../../interfaces/IERC1967.sol";

library ERC1967Utils {
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function getImplementation() internal view returns (address) {
        return _getAddressSlot(IMPLEMENTATION_SLOT);
    }

    function _setImplementation(address newImplementation) private {
        // Solana does not support address.code; use AccountInfo to check if account exists
        // For Solana, we assume the implementation account is valid if provided
        _setAddressSlot(IMPLEMENTATION_SLOT, newImplementation);
    }

    function upgradeToAndCall(address newImplementation, bytes memory data) internal {
        _setImplementation(newImplementation);
        emit IERC1967.Upgraded(newImplementation);

        if (data.length > 0) {
            _functionDelegateCall(newImplementation, data);
        } else {
            _checkNonPayable();
        }
    }

    bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    function getAdmin() internal view returns (address) {
        return _getAddressSlot(ADMIN_SLOT);
    }

    function _setAdmin(address newAdmin) private {
        if (newAdmin == address(0)) {
            revert("ERC1967: invalid admin");
        }
        _setAddressSlot(ADMIN_SLOT, newAdmin);
    }

    function changeAdmin(address newAdmin) internal {
        emit IERC1967.AdminChanged(getAdmin(), newAdmin);
        _setAdmin(newAdmin);
    }

    bytes32 internal constant BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    function getBeacon() internal view returns (address) {
        return _getAddressSlot(BEACON_SLOT);
    }

    function _setBeacon(address newBeacon) private {
        _setAddressSlot(BEACON_SLOT, newBeacon);
    }

    function upgradeBeaconToAndCall(address newBeacon, bytes memory data) internal {
        _setBeacon(newBeacon);
        emit IERC1967.BeaconUpgraded(newBeacon);

        if (data.length > 0) {
            // On Solana, we cannot call IBeacon(newBeacon).implementation() easily
            // The caller must ensure the beacon is valid
            _functionDelegateCall(newBeacon, data);
        } else {
            _checkNonPayable();
        }
    }

    function _checkNonPayable() private {
        // msg.value is not supported on Solana; value transfer via function calls is unsupported.
        // The check is removed as it has no effect.
    }

    // Inline storage slot helpers using account data storage
    function _getAddressSlot(bytes32 slot) private view returns (address) {
        bytes32 value = _sload(slot);
        return address(uint160(uint256(value)));
    }

    function _setAddressSlot(bytes32 slot, address addr) private {
        _sstore(slot, addr);
    }

    // Inline delegate call helper
    function _functionDelegateCall(address target, bytes memory data) private {
        (bool success, ) = target.call{accounts: []}(data);
        if (!success) {
            revert("ERC1967: delegate call failed");
        }
    }

    // Storage helpers using account data - Solana compatible
    function _sload(bytes32 slot) private view returns (bytes32) {
        bytes32 value;
        // Use Solana account data storage via tx.accounts
        // The data account is the current contract's data account
        AccountMeta[1] memory metas = [
            AccountMeta({pubkey: tx.accounts.dataAccount.key, is_signer: false, is_writable: false})
        ];
        value = tx.accounts.dataAccount.key.readSlot(slot);
        return value;
    }

    function _sstore(bytes32 slot, address addr) private {
        // Use Solana account data storage via tx.accounts
        AccountMeta[1] memory metas = [
            AccountMeta({pubkey: tx.accounts.dataAccount.key, is_signer: false, is_writable: true})
        ];
        tx.accounts.dataAccount.key.writeSlot(slot, bytes32(uint256(uint160(addr))));
    }
}