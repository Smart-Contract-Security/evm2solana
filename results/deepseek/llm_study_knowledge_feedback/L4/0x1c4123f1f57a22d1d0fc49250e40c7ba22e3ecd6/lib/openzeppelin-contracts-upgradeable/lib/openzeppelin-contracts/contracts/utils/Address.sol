// SPDX-License-Identifier: MIT

library Address {
    function sendValue(address payable recipient, uint64 amount) internal {
        if (tx.accounts.dataAccount.lamports < amount) {
            revert("InsufficientBalance");
        }
        revert("FailedCall");
    }

    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0);
    }

    function functionCallWithValue(address target, bytes memory data, uint64 value) internal returns (bytes memory) {
        if (tx.accounts.dataAccount.lamports < value) {
            revert("InsufficientBalance");
        }
        revert("FailedCall");
    }

    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        revert("FailedCall");
    }

    function verifyCallResultFromTarget(
        address target,
        bool success,
        bytes memory returndata
    ) internal view returns (bytes memory) {
        if (success && returndata.length > 0) {
            return returndata;
        } else if (success) {
            revert("AddressEmptyCode");
        } else if (returndata.length > 0) {
            revert("FailedCall");
        } else {
            revert("FailedCall");
        }
    }

    function verifyCallResult(bool success, bytes memory returndata) internal pure returns (bytes memory) {
        if (success) {
            return returndata;
        } else if (returndata.length > 0) {
            revert("FailedCall");
        } else {
            revert("FailedCall");
        }
    }
}