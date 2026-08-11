// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC1822Proxiable} from "../../interfaces/draft-IERC1822.sol";

abstract contract UUPSUpgradeable is IERC1822Proxiable {
    address private immutable __self;

    // ERC1967 storage slot for implementation
    bytes32 private constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    constructor() {
        __self = address(this);
    }

    string public constant UPGRADE_INTERFACE_VERSION = "5.0.0";

    modifier onlyProxy() {
        _checkProxy();
        _;
    }

    modifier notDelegated() {
        _checkNotDelegated();
        _;
    }

    function proxiableUUID() external view virtual notDelegated returns (bytes32) {
        return IMPLEMENTATION_SLOT;
    }

    function upgradeToAndCall(address newImplementation, bytes memory data) public payable virtual onlyProxy {
        _authorizeUpgrade(newImplementation);
        _upgradeToAndCallUUPS(newImplementation, data);
    }

    function _checkProxy() internal view virtual {
        if (
            address(this) == __self ||
            getImplementation() != __self
        ) {
            revert("UUPSUnauthorizedCallContext");
        }
    }

    function _checkNotDelegated() internal view virtual {
        if (address(this) != __self) {
            revert("UUPSUnauthorizedCallContext");
        }
    }

    function _authorizeUpgrade(address newImplementation) internal virtual;

    function _upgradeToAndCallUUPS(address newImplementation, bytes memory data) private {
        AccountMeta[1] memory metas = [AccountMeta({pubkey: newImplementation, is_signer: false, is_writable: false})];
        (bool success, bytes memory returnData) = newImplementation.call{accounts: metas}(
            abi.encodeWithSelector(IERC1822Proxiable.proxiableUUID.selector)
        );
        if (success) {
            bytes32 slot = abi.decode(returnData, (bytes32));
            if (slot != IMPLEMENTATION_SLOT) {
                revert("UUPSUnsupportedProxiableUUID");
            }
            upgradeToAndCallImpl(newImplementation, data);
        } else {
            revert("ERC1967InvalidImplementation");
        }
    }

    function getImplementation() internal view returns (address) {
        return _getImplementation();
    }

    function _getImplementation() private view returns (address impl) {
        bytes32 slot = IMPLEMENTATION_SLOT;
        impl = _sload(slot);
    }

    function upgradeToAndCallImpl(address newImplementation, bytes memory data) internal {
        _setImplementation(newImplementation);
        if (data.length > 0) {
            AccountMeta[1] memory metas = [AccountMeta({pubkey: newImplementation, is_signer: false, is_writable: false})];
            (bool success, ) = newImplementation.call{accounts: metas}(data);
            require(success, "ERC1967 upgrade failed");
        }
    }

    function _setImplementation(address newImplementation) private {
        bytes32 slot = IMPLEMENTATION_SLOT;
        _sstore(slot, newImplementation);
    }

    function _sload(bytes32 slot) private view returns (address value) {
        bytes32 data = tx.accounts.data[slot];
        assembly {
            value := data
        }
    }

    function _sstore(bytes32 slot, address value) private {
        tx.accounts.data[slot] = bytes32(uint256(uint160(value)));
    }
}