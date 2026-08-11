// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Initializable} from "./Initializable.sol";

abstract contract UUPSUpgradeable is Initializable {
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

    function __UUPSUpgradeable_init() internal onlyInitializing {
    }

    function __UUPSUpgradeable_init_unchained() internal onlyInitializing {
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
            _getImplementation() != __self
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
        bytes32 slot = _tryProxiableUUID(newImplementation);
        if (slot == bytes32(0)) {
            revert("ERC1967InvalidImplementation");
        }
        if (slot != IMPLEMENTATION_SLOT) {
            revert("UUPSUnsupportedProxiableUUID");
        }
        _upgradeToAndCall(newImplementation, data);
    }

    function _tryProxiableUUID(address target) private view returns (bytes32) {
        (bool success, bytes memory result) = target.call{accounts: [target]}(abi.encodeWithSignature("proxiableUUID()"));
        if (success && result.length == 32) {
            return abi.decode(result, (bytes32));
        }
        return bytes32(0);
    }

    function _getImplementation() internal view returns (address) {
        return _getAddressSlot(IMPLEMENTATION_SLOT);
    }

    function _getAddressSlot(bytes32 slot) internal view returns (address r) {
        bytes32 value = _sload(slot);
        r = address(uint160(uint256(value)));
    }

    function _sload(bytes32 slot) private view returns (bytes32 value) {
        assembly {
            value := sload(slot)
        }
    }

    function _upgradeToAndCall(address newImplementation, bytes memory data) internal {
        _setImplementation(newImplementation);
        if (data.length > 0) {
            (bool success, ) = newImplementation.call{accounts: [newImplementation]}(data);
            require(success, "delegatecall failed");
        }
    }

    function _setImplementation(address newImplementation) internal {
        require(_isContract(newImplementation), "implementation is not a contract");
        _sstore(IMPLEMENTATION_SLOT, bytes32(uint256(uint160(newImplementation))));
    }

    function _isContract(address addr) private view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }

    function _sstore(bytes32 slot, bytes32 value) private {
        assembly {
            sstore(slot, value)
        }
    }
}