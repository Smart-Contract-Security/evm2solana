// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.5.0) (utils/LowLevelCall.sol)

import 'solana';

library LowLevelCall {
    /// @dev Performs a Solidity function call using a low level `call` and ignoring the return data.
    function callNoReturn(address target, bytes memory data) internal returns (bool success) {
        return callNoReturn(target, 0, data);
    }

    /// @dev Same as {callNoReturn}, but allows to specify the value to be sent in the call.
    function callNoReturn(address target, uint64 value, bytes memory data) internal returns (bool success) {
        (success, ) = target.call{accounts: []}(data);
    }

    /// @dev Performs a Solidity function call using a low level `call` and returns the first 64 bytes of the result
    /// in the scratch space of memory. Useful for functions that return a tuple of single-word values.
    ///
    /// WARNING: Do not assume that the results are zero if `success` is false. Memory can be already allocated
    /// and this function doesn't zero it out.
    function callReturn64Bytes(
        address target,
        bytes memory data
    ) internal returns (bool success, bytes32 result1, bytes32 result2) {
        return callReturn64Bytes(target, 0, data);
    }

    /// @dev Same as {callReturnBytes32Pair}, but allows to specify the value to be sent in the call.
    function callReturn64Bytes(
        address target,
        uint64 value,
        bytes memory data
    ) internal returns (bool success, bytes32 result1, bytes32 result2) {
        bytes memory returndata = new bytes(64);
        (success, returndata) = target.call{accounts: []}(data);
        if (returndata.length >= 32) {
            result1 = bytes32(returndata[0:32]);
        }
        if (returndata.length >= 64) {
            result2 = bytes32(returndata[32:64]);
        }
    }

    /// @dev Performs a Solidity function call using a low level `staticcall` and ignoring the return data.
    function staticcallNoReturn(address target, bytes memory data) internal view returns (bool success) {
        (success, ) = target.call{accounts: []}(data);
    }

    /// @dev Performs a Solidity function call using a low level `staticcall` and returns the first 64 bytes of the result
    /// in the scratch space of memory. Useful for functions that return a tuple of single-word values.
    ///
    /// WARNING: Do not assume that the results are zero if `success` is false. Memory can be already allocated
    /// and this function doesn't zero it out.
    function staticcallReturn64Bytes(
        address target,
        bytes memory data
    ) internal view returns (bool success, bytes32 result1, bytes32 result2) {
        bytes memory returndata = new bytes(64);
        (success, returndata) = target.call{accounts: []}(data);
        if (returndata.length >= 32) {
            result1 = bytes32(returndata[0:32]);
        }
        if (returndata.length >= 64) {
            result2 = bytes32(returndata[32:64]);
        }
    }

    /// @dev delegatecall is not available on Solana.
    function delegatecallNoReturn(address target, bytes memory data) internal returns (bool success) {
        revert("delegatecall not supported on Solana");
    }

    /// @dev delegatecall is not available on Solana.
    function delegatecallReturn64Bytes(
        address target,
        bytes memory data
    ) internal returns (bool success, bytes32 result1, bytes32 result2) {
        revert("delegatecall not supported on Solana");
    }

    /// @dev Returns the size of the return data buffer.
    function returnDataSize() internal pure returns (uint64 size) {
        // returndatasize is not available on Solana.
        // This function is kept for compatibility but cannot be implemented.
        revert("returndatasize not supported on Solana");
    }

    /// @dev Returns a buffer containing the return data from the last call.
    function returnData() internal pure returns (bytes memory result) {
        // returndatacopy is not available on Solana.
        // This function is kept for compatibility but cannot be implemented.
        revert("returndatacopy not supported on Solana");
    }

    /// @dev Revert with the return data from the last call.
    function bubbleRevert() internal pure {
        // returndatacopy and revert with data are not available on Solana.
        revert("bubbleRevert not supported on Solana");
    }

    function bubbleRevert(bytes memory returndata) internal pure {
        revert(string(returndata));
    }
}