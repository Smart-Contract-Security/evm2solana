// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Errors} from "./Errors.sol";

library Address {
    error AddressEmptyCode(address target);

    function sendValue(address payable recipient, uint256 amount) internal {
        if (recipient.lamports < amount) {
            revert Errors.InsufficientBalance(recipient.lamports, amount);
        }
        recipient.transfer(amount);
    }

    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0);
    }

    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        if (target.lamports < value) {
            revert Errors.InsufficientBalance(target.lamports, value);
        }
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        if (success && (returndata.length > 0 || target.code.length > 0)) {
            return returndata;
        } else if (success) {
            revert AddressEmptyCode(target);
        } else if (returndata.length > 0) {
            revert(string(returndata));
        } else {
            revert("FailedCall");
        }
    }

    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        (bool success, bytes memory returndata) = target.call(data);
        if (success && (returndata.length > 0 || target.code.length > 0)) {
            return returndata;
        } else if (success) {
            revert AddressEmptyCode(target);
        } else if (returndata.length > 0) {
            revert(string(returndata));
        } else {
            revert("FailedCall");
        }
    }

    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        (bool success, bytes memory returndata) = target.call(data);
        if (success && (returndata.length > 0 || target.code.length > 0)) {
            return returndata;
        } else if (success) {
            revert AddressEmptyCode(target);
        } else if (returndata.length > 0) {
            revert(string(returndata));
        } else {
            revert("FailedCall");
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
            revert(string(returndata));
        } else {
            revert("FailedCall");
        }
    }

    function verifyCallResult(bool success, bytes memory returndata) internal pure returns (bytes memory) {
        if (success) {
            return returndata;
        } else if (returndata.length > 0) {
            revert(string(returndata));
        } else {
            revert("FailedCall");
        }
    }
}