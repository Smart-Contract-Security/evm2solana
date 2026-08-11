// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IERC1822Proxiable} from "../../interfaces/draft-IERC1822.sol";

abstract contract UUPSUpgradeable is IERC1822Proxiable {
    address private immutable __self;

    bytes32 public constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    constructor() {
        __self = address(this);
    }

    string public constant UPGRADE_INTERFACE_VERSION = "5.0.0";

    error UUPSUnauthorizedCallContext();
    error UUPSUnsupportedProxiableUUID(bytes32 slot);
    error ERC1967InvalidImplementation(address implementation);

    modifier onlyProxy() {
        _checkProxy();
        _;
    }

    modifier notDelegated() {
        _checkNotDelegated();
        _;
    }

    function proxiableUUID() external view notDelegated returns (bytes32) {
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

    function _getImplementation() internal view returns (address) {
        bytes32 slot = IMPLEMENTATION_SLOT;
        bytes32 value = _sload(slot);
        return address(uint160(uint256(value)));
    }

    function _sload(bytes32 slot) private view returns (bytes32 value) {
        assembly {
            value := sload(slot)
        }
    }

    function _upgradeToAndCallUUPS(address newImplementation, bytes memory data) private {
        bytes memory returndata = _callWithNoRevert(newImplementation, abi.encodeWithSelector(IERC1822Proxiable.proxiableUUID.selector));
        if (returndata.length == 0) {
            revert("ERC1967InvalidImplementation");
        }
        bytes32 slot = abi.decode(returndata, (bytes32));
        if (slot != IMPLEMENTATION_SLOT) {
            revert("UUPSUnsupportedProxiableUUID");
        }
        _upgradeToAndCall(newImplementation, data);
    }

    function _callWithNoRevert(address target, bytes memory data) private returns (bytes memory) {
        (bool success, bytes memory returndata) = target.call{accounts: [target]}(data);
        if (!success) {
            return "";
        }
        return returndata;
    }

    function _upgradeToAndCall(address newImplementation, bytes memory data) private {
        bytes32 slot = IMPLEMENTATION_SLOT;
        _sstore(slot, bytes32(uint256(uint160(newImplementation))));
        if (data.length > 0) {
            (bool success, ) = newImplementation.call{accounts: [newImplementation]}(data);
            require(success, "ERC1967: upgrade call failed");
        }
    }

    function _sstore(bytes32 slot, bytes32 value) private {
        assembly {
            sstore(slot, value)
        }
    }
}