// SPDX-License-Identifier: MIT

import 'solana';

library ERC1967Utils {
    bytes32 constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function getImplementation() internal view returns (address) {
        return getAddressSlot(IMPLEMENTATION_SLOT);
    }

    function upgradeToAndCall(address newImplementation, bytes memory data) internal {
        setAddressSlot(IMPLEMENTATION_SLOT, newImplementation);
        if (data.length > 0) {
            AccountMeta[1] metas = [
                AccountMeta({pubkey: newImplementation, is_signer: false, is_writable: true})
            ];
            (bool success, ) = newImplementation.call{accounts: metas}(data);
            require(success, "ERC1967: upgrade failed");
        }
    }

    function getAddressSlot(bytes32 slot) private view returns (address result) {
        bytes32[1] storage slots;
        assembly {
            slots.slot := slot
        }
        result = address(uint256(slots[0]));
    }

    function setAddressSlot(bytes32 slot, address value) private {
        bytes32[1] storage slots;
        assembly {
            slots.slot := slot
        }
        slots[0] = bytes32(uint256(uint160(value)));
    }
}

interface IERC1822Proxiable {
    function proxiableUUID() external view returns (bytes32);
}

abstract contract UUPSUpgradeable is IERC1822Proxiable {
    address private immutable __self;

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

    function proxiableUUID() external view notDelegated returns (bytes32) {
        return ERC1967Utils.IMPLEMENTATION_SLOT;
    }

    function upgradeToAndCall(address newImplementation, bytes memory data) public onlyProxy {
        _authorizeUpgrade(newImplementation);
        _upgradeToAndCallUUPS(newImplementation, data);
    }

    function _checkProxy() internal view virtual {
        if (
            address(this) == __self ||
            ERC1967Utils.getImplementation() != __self
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
        bytes32 slot = IERC1822Proxiable(newImplementation).proxiableUUID();
        if (slot != ERC1967Utils.IMPLEMENTATION_SLOT) {
            revert("UUPSUnsupportedProxiableUUID");
        }
        ERC1967Utils.upgradeToAndCall(newImplementation, data);
    }
}