// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

library Address {
    // On Solana, accounts are always programs or owned by programs.
    // We check if the account has executable data by checking if it's a program-derived address or has code.
    // Since Solang does not support account.code, we use a simple heuristic:
    // For Solana, we assume the account is a contract if it's not the zero address.
    // In practice, you would pass an additional flag or use syscalls, but for porting we simplify.
    function isContract(address account) internal view returns (bool) {
        // Solana: all addresses can be programs. We return true for non-zero addresses.
        // This is a simplification; real checks require external program introspection.
        return account != address(0);
    }

    function sendValue(address payable recipient, uint256 amount) internal {
        // On Solana, balance is not available via address(this).balance.
        // We require the caller to pass the account's lamports via tx.accounts.
        // Since this is a library, we cannot access tx.accounts directly.
        // We'll assume the balance check is done externally or we skip it.
        // For porting, we remove the balance check and rely on the runtime to fail if insufficient.
        // (bool success, ) = recipient.call{value: amount}("");
        // Solang does not support .call{value: amount}("") on Solana.
        // We replace with a transfer via system program, but that requires accounts.
        // As a library, we cannot perform cross-program invocation without accounts.
        // We'll leave a placeholder that reverts with a message.
        revert("Address: sendValue not supported on Solana via library");
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
        // Solana: balance and call with value not supported in libraries.
        // We revert with a message.
        revert("Address: functionCallWithValue not supported on Solana via library");
    }

    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    function functionStaticCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        // Solana: staticcall not supported.
        revert("Address: functionStaticCall not supported on Solana via library");
    }

    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }

    function functionDelegateCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        // Solana: delegatecall not supported.
        revert("Address: functionDelegateCall not supported on Solana via library");
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
            // Solana: mload not available. We revert with a generic message.
            // We cannot decode the returndata easily without assembly.
            // We'll just revert with the errorMessage.
            revert(errorMessage);
        } else {
            revert(errorMessage);
        }
    }
}