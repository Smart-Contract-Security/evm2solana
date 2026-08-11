// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (proxy/utils/UUPSUpgradeable.sol)

import {ERC1967Utils} from "../ERC1967/ERC1967Utils.sol";

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
            revert();
        }
    }

    function _checkNotDelegated() internal view virtual {
        if (address(this) != __self) {
            revert();
        }
    }

    function _authorizeUpgrade(address newImplementation) internal virtual;

    function _upgradeToAndCallUUPS(address newImplementation, bytes memory data) private {
        bytes32 slot = IERC1822Proxiable(newImplementation).proxiableUUID();
        if (slot != ERC1967Utils.IMPLEMENTATION_SLOT) {
            revert();
        }
        ERC1967Utils.upgradeToAndCall(newImplementation, data);
    }
}