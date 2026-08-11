// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface IBeacon {
    function implementation() external view returns (address);
}

contract BeaconProxy {
    address private immutable _beacon;

    constructor(address beacon, bytes memory data) payable {
        _beacon = beacon;
        if (data.length > 0) {
            address impl = IBeacon(beacon).implementation();
            require(impl != address(0), "BeaconProxy: implementation not set");
            (bool success, ) = impl.delegatecall(data);
            require(success, "BeaconProxy: initialization failed");
        }
    }

    fallback() external {
        address impl = _implementation();
        require(impl != address(0), "BeaconProxy: implementation not set");
        bytes memory callData = msg.data;
        (bool success, bytes memory returnData) = impl.delegatecall(callData);
        if (!success) {
            if (returnData.length > 0) {
                assembly {
                    revert(add(returnData, 32), mload(returnData))
                }
            } else {
                revert("BeaconProxy: delegatecall failed");
            }
        }
        assembly {
            return(add(returnData, 32), mload(returnData))
        }
    }

    function _implementation() internal view returns (address) {
        return IBeacon(_getBeacon()).implementation();
    }

    function _getBeacon() internal view returns (address) {
        return _beacon;
    }
}