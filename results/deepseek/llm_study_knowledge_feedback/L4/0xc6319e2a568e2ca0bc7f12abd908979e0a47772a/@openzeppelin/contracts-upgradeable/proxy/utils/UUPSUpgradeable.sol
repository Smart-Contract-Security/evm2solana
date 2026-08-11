// SPDX-License-Identifier: MIT

interface IERC1822ProxiableUpgradeable {
    function proxiableUUID() external view returns (bytes32);
}

abstract contract UUPSUpgradeable is IERC1822ProxiableUpgradeable {
    bytes32 private constant _IMPLEMENTATION_SLOT = hex"360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";

    address private immutable __self;

    constructor() {
        __self = address(this);
    }

    modifier onlyProxy() {
        require(address(this) != __self, "Function must be called through delegatecall");
        require(_getImplementation() == __self, "Function must be called through active proxy");
        _;
    }

    modifier notDelegated() {
        require(address(this) == __self, "UUPSUpgradeable: must not be called through delegatecall");
        _;
    }

    function __UUPSUpgradeable_init() internal {
    }

    function __UUPSUpgradeable_init_unchained() internal {
    }

    function proxiableUUID() external view virtual override notDelegated returns (bytes32) {
        return _IMPLEMENTATION_SLOT;
    }

    function upgradeTo(address newImplementation) public virtual onlyProxy {
        _authorizeUpgrade(newImplementation);
        _upgradeToAndCallUUPS(newImplementation, new bytes(0), false);
    }

    function upgradeToAndCall(address newImplementation, bytes memory data) public virtual onlyProxy {
        _authorizeUpgrade(newImplementation);
        _upgradeToAndCallUUPS(newImplementation, data, true);
    }

    function _authorizeUpgrade(address newImplementation) internal virtual;

    function _getImplementation() internal view returns (address) {
        return address(uint160(uint256(_IMPLEMENTATION_SLOT)));
    }

    function _upgradeToAndCallUUPS(address newImplementation, bytes memory data, bool forceCall) internal virtual;

    uint256[50] private __gap;
}