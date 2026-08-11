// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../interfaces/draft-IERC1822Upgradeable.sol";

abstract contract UUPSUpgradeable is IERC1822ProxiableUpgradeable {
    bytes32 private constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    address private immutable __self;

    // Storage for implementation address (replaces sload/sstore)
    address private _implementation;

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

    function upgradeTo(address newImplementation) external virtual onlyProxy {
        _authorizeUpgrade(newImplementation);
        _upgradeToAndCallUUPS(newImplementation, new bytes(0), false);
    }

    function upgradeToAndCall(address newImplementation, bytes memory data) external payable virtual onlyProxy {
        _authorizeUpgrade(newImplementation);
        _upgradeToAndCallUUPS(newImplementation, data, true);
    }

    function _authorizeUpgrade(address newImplementation) internal virtual;

    function _getImplementation() internal view returns (address) {
        return _implementation;
    }

    function _upgradeToAndCallUUPS(address newImplementation, bytes memory data, bool forceCall) internal {
        _implementation = newImplementation;
        if (data.length > 0 || forceCall) {
            (bool success, bytes memory returndata) = newImplementation.call{accounts: [newImplementation]}(data);
            require(success, string(returndata));
        }
    }

    uint256[50] private __gap;
}