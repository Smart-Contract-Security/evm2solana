// SPDX-License-Identifier: MIT

import {Initializable} from "./Initializable.sol";

interface IERC1822Proxiable {
    function proxiableUUID() external view returns (bytes32);
}

library ERC1967Utils {
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function getImplementation() internal view returns (address) {
        return getAddressSlot(IMPLEMENTATION_SLOT).value;
    }

    function upgradeToAndCall(address newImplementation, bytes memory data) internal {
        setAddressSlot(IMPLEMENTATION_SLOT, newImplementation);
        if (data.length > 0) {
            (bool success, bytes memory returndata) = newImplementation.call{abi.encodeWithSignature("upgradeToAndCall(address,bytes)", newImplementation, data)}("");
            if (!success) {
                if (returndata.length > 0) {
                    revert(string(returndata));
                } else {
                    revert("ERC1967UpgradeFailed");
                }
            }
        }
    }

    struct AddressSlot {
        address value;
    }

    function getAddressSlot(bytes32 slot) private pure returns (AddressSlot storage r) {
        assembly {
            r.slot := slot
        }
    }

    function setAddressSlot(bytes32 slot, address value) private {
        assembly {
            sstore(slot, value)
        }
    }
}

abstract contract UUPSUpgradeable is Initializable, IERC1822Proxiable {
    address private immutable __self;

    string public constant UPGRADE_INTERFACE_VERSION = "5.0.0";

    constructor() {
        __self = address(this);
    }

    modifier onlyProxy() {
        _checkProxy();
        _;
    }

    modifier notDelegated() {
        _checkNotDelegated();
        _;
    }

    function __UUPSUpgradeable_init() internal onlyInitializing {
    }

    function __UUPSUpgradeable_init_unchained() internal onlyInitializing {
    }

    function proxiableUUID() external view virtual notDelegated returns (bytes32) {
        return ERC1967Utils.IMPLEMENTATION_SLOT;
    }

    function upgradeToAndCall(address newImplementation, bytes memory data) public virtual onlyProxy {
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