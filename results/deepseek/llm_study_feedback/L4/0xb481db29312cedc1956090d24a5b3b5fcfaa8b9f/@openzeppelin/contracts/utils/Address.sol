// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library Address {
    error AddressEmptyCode(address target);
    error InsufficientBalance(uint256 balance, uint256 amount);
    error FailedCall();

    function sendValue(address payable recipient, uint256 amount) internal {
        uint256 recipientBalance = recipient.lamports;
        if (recipientBalance < amount) {
            revert InsufficientBalance(recipientBalance, amount);
        }

        (bool success, bytes memory returndata) = recipient.call{value: amount}("");
        if (!success) {
            _revert(returndata);
        }
    }

    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0);
    }

    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        uint256 targetBalance = target.lamports;
        if (targetBalance < value) {
            revert InsufficientBalance(targetBalance, value);
        }
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        (bool success, bytes memory returndata) = target.call(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        (bool success, bytes memory returndata) = target.call(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    function verifyCallResultFromTarget(
        address target,
        bool success,
        bytes memory returndata
    ) internal view returns (bytes memory) {
        if (!success) {
            _revert(returndata);
        } else {
            // On Solana, address.code is not available. We skip the empty code check.
            // The caller should ensure the target is a valid program.
            return returndata;
        }
    }

    function verifyCallResult(bool success, bytes memory returndata) internal pure returns (bytes memory) {
        if (!success) {
            _revert(returndata);
        } else {
            return returndata;
        }
    }

    function _revert(bytes memory returndata) private pure {
        if (returndata.length > 0) {
            revert(string(returndata));
        } else {
            revert("Address: call failed");
        }
    }
}