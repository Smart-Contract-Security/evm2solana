// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library LowLevelCall {
    function callNoReturn(address target, bytes memory data) internal returns (bool success) {
        return callNoReturn(target, 0, data);
    }

    function callNoReturn(address target, uint256 value, bytes memory data) internal returns (bool success) {
        (success, ) = target.call{value: value}(data);
    }

    function callReturn64Bytes(
        address target,
        bytes memory data
    ) internal returns (bool success, bytes32 result1, bytes32 result2) {
        return callReturn64Bytes(target, 0, data);
    }

    function callReturn64Bytes(
        address target,
        uint256 value,
        bytes memory data
    ) internal returns (bool success, bytes32 result1, bytes32 result2) {
        bytes memory ret;
        (success, ret) = target.call{value: value}(data);
        if (success && ret.length >= 64) {
            assembly {
                result1 := mload(add(ret, 32))
                result2 := mload(add(ret, 64))
            }
        }
    }

    function staticcallNoReturn(address target, bytes memory data) internal view returns (bool success) {
        (success, ) = target.staticcall(data);
    }

    function staticcallReturn64Bytes(
        address target,
        bytes memory data
    ) internal view returns (bool success, bytes32 result1, bytes32 result2) {
        bytes memory ret;
        (success, ret) = target.staticcall(data);
        if (success && ret.length >= 64) {
            assembly {
                result1 := mload(add(ret, 32))
                result2 := mload(add(ret, 64))
            }
        }
    }

    function delegatecallNoReturn(address target, bytes memory data) internal returns (bool success) {
        (success, ) = target.delegatecall(data);
    }

    function delegatecallReturn64Bytes(
        address target,
        bytes memory data
    ) internal returns (bool success, bytes32 result1, bytes32 result2) {
        bytes memory ret;
        (success, ret) = target.delegatecall(data);
        if (success && ret.length >= 64) {
            assembly {
                result1 := mload(add(ret, 32))
                result2 := mload(add(ret, 64))
            }
        }
    }

    function returnDataSize() internal pure returns (uint256 size) {
        assembly {
            size := returndatasize()
        }
    }

    function returnData() internal pure returns (bytes memory result) {
        assembly {
            result := mload(0x40)
            mstore(result, returndatasize())
            returndatacopy(add(result, 0x20), 0x00, returndatasize())
            mstore(0x40, add(result, add(0x20, returndatasize())))
        }
    }

    function bubbleRevert() internal pure {
        assembly {
            let fmp := mload(0x40)
            returndatacopy(fmp, 0x00, returndatasize())
            revert(fmp, returndatasize())
        }
    }

    function bubbleRevert(bytes memory returndata) internal pure {
        assembly {
            revert(add(returndata, 0x20), mload(returndata))
        }
    }
}