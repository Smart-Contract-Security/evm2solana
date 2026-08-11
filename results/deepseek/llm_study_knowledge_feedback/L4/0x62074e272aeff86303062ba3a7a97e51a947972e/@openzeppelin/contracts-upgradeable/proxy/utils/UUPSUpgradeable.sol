// SPDX-License-Identifier: MIT

interface IERC1822Proxiable {
    function proxiableUUID() external view returns (bytes32);
}

abstract contract UUPSUpgradeable is IERC1822Proxiable {
    address private immutable __self;

    string public constant UPGRADE_INTERFACE_VERSION = "5.0.0";

    bytes32 private constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

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

    function proxiableUUID() external view virtual notDelegated returns (bytes32) {
        return IMPLEMENTATION_SLOT;
    }

    function upgradeToAndCall(address newImplementation, bytes memory data) public virtual onlyProxy {
        _authorizeUpgrade(newImplementation);
        _upgradeToAndCallUUPS(newImplementation, data);
    }

    function _checkProxy() internal view virtual {
        if (
            address(this) == __self ||
            getImplementation() != __self
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
        if (slot != IMPLEMENTATION_SLOT) {
            revert();
        }
        _upgradeToAndCall(newImplementation, data);
    }

    function getImplementation() internal view returns (address) {
        return _getAddress(IMPLEMENTATION_SLOT);
    }

    function _upgradeToAndCall(address newImplementation, bytes memory data) internal {
        _setAddress(IMPLEMENTATION_SLOT, newImplementation);
        if (data.length > 0) {
            (bool success, ) = newImplementation.call(data);
            require(success);
        }
    }

    function _getAddress(bytes32 slot) private view returns (address addr) {
        addr = address(uint160(uint256(slot)));
    }

    function _setAddress(bytes32 slot, address addr) private {
        slot = bytes32(uint256(uint160(addr)));
    }
}