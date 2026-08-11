// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Errors} from "./Errors.sol";

library LowLevelCall {
    function callNoReturn(address target, uint256 value, bytes memory data) internal returns (bool) {
        (bool success, ) = target.call{value: value}(data);
        return success;
    }

    function staticcallNoReturn(address target, bytes memory data) internal view returns (bool) {
        (bool success, ) = target.staticcall(data);
        return success;
    }

    function delegatecallNoReturn(address target, bytes memory data) internal returns (bool) {
        (bool success, ) = target.delegatecall(data);
        return success;
    }

    function returnDataSize() internal pure returns (uint256) {
        uint256 size;
        assembly {
            size := returndatasize()
        }
        return size;
    }

    function returnData() internal pure returns (bytes memory) {
        uint256 size = returnDataSize();
        bytes memory data = new bytes(size);
        assembly {
            returndatacopy(add(data, 0x20), 0, size)
        }
        return data;
    }

    function bubbleRevert() internal pure {
        uint256 size = returnDataSize();
        if (size > 0) {
            bytes memory data = returnData();
            assembly {
                revert(add(data, 0x20), size)
            }
        } else {
            revert("LowLevelCall: call failed");
        }
    }

    function bubbleRevert(bytes memory data) internal pure {
        assembly {
            revert(add(data, 0x20), mload(data))
        }
    }
}

library Address {
    error AddressEmptyCode(address target);

    function sendValue(address payable recipient, uint256 amount) internal {
        if (address(this).balance < amount) {
            revert Errors.InsufficientBalance(address(this).balance, amount);
        }
        if (LowLevelCall.callNoReturn(recipient, amount, "")) {
            return;
        } else if (LowLevelCall.returnDataSize() > 0) {
            LowLevelCall.bubbleRevert();
        } else {
            revert Errors.FailedCall();
        }
    }

    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0);
    }

    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        if (address(this).balance < value) {
            revert Errors.InsufficientBalance(address(this).balance, value);
        }
        bool success = LowLevelCall.callNoReturn(target, value, data);
        if (success && (LowLevelCall.returnDataSize() > 0 || target.code.length > 0)) {
            return LowLevelCall.returnData();
        } else if (success) {
            revert AddressEmptyCode(target);
        } else if (LowLevelCall.returnDataSize() > 0) {
            LowLevelCall.bubbleRevert();
        } else {
            revert Errors.FailedCall();
        }
    }

    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        bool success = LowLevelCall.staticcallNoReturn(target, data);
        if (success && (LowLevelCall.returnDataSize() > 0 || target.code.length > 0)) {
            return LowLevelCall.returnData();
        } else if (success) {
            revert AddressEmptyCode(target);
        } else if (LowLevelCall.returnDataSize() > 0) {
            LowLevelCall.bubbleRevert();
        } else {
            revert Errors.FailedCall();
        }
    }

    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        bool success = LowLevelCall.delegatecallNoReturn(target, data);
        if (success && (LowLevelCall.returnDataSize() > 0 || target.code.length > 0)) {
            return LowLevelCall.returnData();
        } else if (success) {
            revert AddressEmptyCode(target);
        } else if (LowLevelCall.returnDataSize() > 0) {
            LowLevelCall.bubbleRevert();
        } else {
            revert Errors.FailedCall();
        }
    }

    function verifyCallResultFromTarget(
        address target,
        bool success,
        bytes memory returndata
    ) internal view returns (bytes memory) {
        if (success && (returndata.length > 0 || target.code.length > 0)) {
            return returndata;
        } else if (success) {
            revert AddressEmptyCode(target);
        } else if (returndata.length > 0) {
            LowLevelCall.bubbleRevert(returndata);
        } else {
            revert Errors.FailedCall();
        }
    }

    function verifyCallResult(bool success, bytes memory returndata) internal pure returns (bytes memory) {
        if (success) {
            return returndata;
        } else if (returndata.length > 0) {
            LowLevelCall.bubbleRevert(returndata);
        } else {
            revert Errors.FailedCall();
        }
    }
}