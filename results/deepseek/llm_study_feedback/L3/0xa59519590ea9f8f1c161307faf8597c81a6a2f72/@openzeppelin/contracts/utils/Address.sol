// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library Address {
    function sendValue(address payable recipient, uint256 amount) internal {
        if (tx.accounts[0].lamports < amount) {
            revert("AddressInsufficientBalance");
        }

        (bool success, ) = recipient.call{value: amount, accounts: [AccountMeta({pubkey: recipient, is_signer: false, is_writable: true})]}("");
        if (!success) {
            revert("FailedInnerCall");
        }
    }

    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0);
    }

    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        if (tx.accounts[0].lamports < value) {
            revert("AddressInsufficientBalance");
        }
        (bool success, bytes memory returndata) = target.call{value: value, accounts: [AccountMeta({pubkey: target, is_signer: false, is_writable: true})]}(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        (bool success, bytes memory returndata) = target.call{accounts: [AccountMeta({pubkey: target, is_signer: false, is_writable: false})]}(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        (bool success, bytes memory returndata) = target.call{accounts: [AccountMeta({pubkey: target, is_signer: false, is_writable: true})]}(data);
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
            if (returndata.length == 0) {
            }
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
            revert("FailedInnerCall");
        } else {
            revert("FailedInnerCall");
        }
    }
}