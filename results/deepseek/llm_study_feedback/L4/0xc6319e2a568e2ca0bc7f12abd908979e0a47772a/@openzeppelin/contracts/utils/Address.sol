// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library Address {
    // Custom errors are not supported on Solana; use string revert messages instead.
    // error AddressInsufficientBalance(address account);
    // error AddressEmptyCode(address target);
    // error FailedInnerCall();

    function sendValue(address payable recipient, uint256 amount) internal {
        // Use tx.accounts to access lamports. The caller must pass the library's own account.
        // Since this is a library, we assume the calling contract passes its own account as 'self'.
        // For simplicity, we require the caller to pass the account via tx.accounts.
        // However, libraries cannot access tx.accounts directly. We'll use a workaround:
        // We'll assume the balance check is done by the caller, or we use a parameter.
        // In Solang, libraries cannot access tx.accounts. We'll modify the function to accept the balance as a parameter.
        // But to keep the interface similar, we'll use a different approach: we'll use the `address(this).balance` replacement.
        // Since `address(this).balance` is not available, we'll use `tx.accounts.self.lamports` where 'self' is the account name.
        // However, the account name is not known in the library. We'll assume the calling contract passes its own account as 'self'.
        // This is a limitation. We'll use a placeholder: we'll require the caller to pass the balance.
        // For the purpose of this port, we'll use a simple revert with string.
        revert("sendValue not supported on Solana without account context");
    }

    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0);
    }

    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        // balance check not possible without account context
        revert("functionCallWithValue not supported on Solana without account context");
    }

    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        // staticcall not available on Solana
        revert("staticcall not supported on Solana");
    }

    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        // delegatecall not available on Solana
        revert("delegatecall not supported on Solana");
    }

    function verifyCallResultFromTarget(
        address target,
        bool success,
        bytes memory returndata
    ) internal view returns (bytes memory) {
        if (!success) {
            _revert(returndata);
        } else {
            // target.code.length not supported on Solana
            // We'll skip the empty code check
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
            // mload not available on Solana. Use inline assembly with Solana-compatible revert.
            // We'll use a simple revert with the data.
            // In Solang, we can use `revert` with bytes.
            // However, custom revert with data is not fully supported. We'll just revert with a string.
            revert("Inner call failed with data");
        } else {
            revert("Failed inner call");
        }
    }
}