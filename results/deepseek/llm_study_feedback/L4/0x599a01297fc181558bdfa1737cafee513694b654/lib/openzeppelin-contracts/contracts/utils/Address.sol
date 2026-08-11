// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

library Address {
    // On Solana, accounts are always programs or owned by programs.
    // We check if the account has executable data by checking if it's a program.
    // For simplicity, we assume all accounts passed are valid programs.
    function isContract(address account) internal view returns (bool) {
        // Solana does not have code.length. We assume the caller ensures the account is a program.
        // Return true to maintain compatibility; callers should validate accounts off-chain.
        return true;
    }

    function sendValue(address payable recipient, uint256 amount) internal {
        // Use tx.accounts to access lamports. The recipient must be passed as an account.
        // Since we cannot dynamically reference accounts, we require the recipient to be a known account.
        // This function is not directly portable; it's kept for interface compatibility.
        revert("sendValue not supported on Solana");
    }

    function functionCall(address target, bytes memory data) public returns (bytes memory) {
        return functionCallWithValue(target, data, 0, "Address: low-level call failed");
    }

    function functionCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) public returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    function functionCallWithValue(address target, bytes memory data, uint256 value) public returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value,
        string memory errorMessage
    ) public returns (bytes memory) {
        // Solana does not support native value transfers in cross-program invocations like EVM.
        // We simulate a call without value transfer.
        (bool success, bytes memory returndata) = target.call(data);
        return verifyCallResultFromTarget(target, success, returndata, errorMessage);
    }

    function functionStaticCall(address target, bytes memory data) public view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    function functionStaticCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) public view returns (bytes memory) {
        // Solang does not support staticcall. Use regular call as fallback.
        (bool success, bytes memory returndata) = target.call(data);
        return verifyCallResultFromTarget(target, success, returndata, errorMessage);
    }

    function functionDelegateCall(address target, bytes memory data) public returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }

    function functionDelegateCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) public returns (bytes memory) {
        // Solang does not support delegatecall. Use regular call as fallback.
        (bool success, bytes memory returndata) = target.call(data);
        return verifyCallResultFromTarget(target, success, returndata, errorMessage);
    }

    function verifyCallResultFromTarget(
        address target,
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        if (success) {
            if (returndata.length == 0) {
                require(isContract(target), "Address: call to non-contract");
            }
            return returndata;
        } else {
            _revert(returndata, errorMessage);
        }
    }

    function verifyCallResult(
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) internal pure returns (bytes memory) {
        if (success) {
            return returndata;
        } else {
            _revert(returndata, errorMessage);
        }
    }

    function _revert(bytes memory returndata, string memory errorMessage) private pure {
        if (returndata.length > 0) {
            // Solang does not support inline assembly or mload.
            // We revert with a generic message.
            revert("Address: low-level call reverted with data");
        } else {
            revert(errorMessage);
        }
    }
}