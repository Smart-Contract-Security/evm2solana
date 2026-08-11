// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

library AddressUpgradeable {
    function isContract(address account) internal view returns (bool) {
        // Solana does not support account.code.length; use tx.accounts to check if account is a program
        // For Solang, we assume an account is a contract if it has data (program) associated.
        // This is a simplified check; in practice, you'd need to check the account's executable flag.
        // Since we cannot access account.code, we return true for non-zero addresses as a heuristic.
        // In Solana, all accounts have data, but only programs are executable.
        // We'll use a placeholder: always return true for non-zero addresses.
        return account != address(0);
    }

    function sendValue(address payable recipient, uint256 amount) internal {
        // Use tx.accounts to access lamports; we need to pass the account name.
        // Since this is a library, we cannot directly access tx.accounts.
        // We'll assume the caller passes the necessary accounts.
        // For simplicity, we'll use a placeholder that requires the caller to ensure balance.
        // In Solang, you can use `address(this).balance` but it's not supported.
        // We'll use `tx.accounts.self.lamports` if the account is named "self".
        // However, library functions don't have named accounts.
        // We'll revert with a message indicating this function is not supported on Solana.
        revert("sendValue not supported on Solana");
    }

    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, "Address: low-level call failed");
    }

    function functionCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value,
        string memory errorMessage
    ) internal returns (bytes memory) {
        // Solana does not support balance or call with value.
        // We'll revert with a message indicating this function is not supported on Solana.
        revert("functionCallWithValue not supported on Solana");
    }

    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    function functionStaticCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        // Solana does not support staticcall.
        // We'll revert with a message indicating this function is not supported on Solana.
        revert("functionStaticCall not supported on Solana");
    }

    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }

    function functionDelegateCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        // Solana does not support delegatecall.
        // We'll revert with a message indicating this function is not supported on Solana.
        revert("functionDelegateCall not supported on Solana");
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
            // Solana does not support inline assembly or mload.
            // We'll revert with the error message instead.
            revert(errorMessage);
        } else {
            revert(errorMessage);
        }
    }
}