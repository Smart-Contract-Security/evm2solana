import 'solana';

library LowLevelCall {
    /// @dev Performs a Solidity function call using a low level `call` and ignoring the return data.
    function callNoReturn(address target, bytes memory data) internal returns (bool success) {
        return callNoReturn(target, 0, data);
    }

    /// @dev Same as {callNoReturn-address-bytes}, but allows specifying the value to be sent in the call.
    function callNoReturn(address target, uint64 value, bytes memory data) internal returns (bool success) {
        AccountMeta[3] metas = [
            AccountMeta({pubkey: tx.accounts.dataAccount.key, is_signer: true, is_writable: true}),
            AccountMeta({pubkey: target, is_signer: false, is_writable: true}),
            AccountMeta({pubkey: address(0), is_signer: false, is_writable: false})
        ];
        bytes memory result = target.call{accounts: metas}(data);
        success = result.length == 0;
    }

    /// @dev Performs a Solidity function call using a low level `call` and returns the first 64 bytes of the result
    /// in the scratch space of memory. Useful for functions that return a tuple with two single-word values.
    ///
    /// WARNING: Do not assume that the results are zero if `success` is false. Memory can be already allocated
    /// and this function doesn't zero it out.
    function callReturn64Bytes(
        address target,
        bytes memory data
    ) internal returns (bool success, bytes32 result1, bytes32 result2) {
        (bool s, bytes32 r1, bytes32 r2) = callReturn64Bytes(target, 0, data);
        success = s;
        result1 = r1;
        result2 = r2;
    }

    /// @dev Same as {callReturn64Bytes-address-bytes}, but allows specifying the value to be sent in the call.
    function callReturn64Bytes(
        address target,
        uint64 value,
        bytes memory data
    ) internal returns (bool success, bytes32 result1, bytes32 result2) {
        AccountMeta[3] metas = [
            AccountMeta({pubkey: tx.accounts.dataAccount.key, is_signer: true, is_writable: true}),
            AccountMeta({pubkey: target, is_signer: false, is_writable: true}),
            AccountMeta({pubkey: address(0), is_signer: false, is_writable: false})
        ];
        bytes memory result = target.call{accounts: metas}(data);
        success = result.length >= 64;
        if (success) {
            result1 = abi.decode(result, (bytes32));
            result2 = abi.decode(result[32:], (bytes32));
        } else {
            result1 = bytes32(0);
            result2 = bytes32(0);
        }
    }

    /// @dev Performs a Solidity function call using a low level `staticcall` and ignoring the return data.
    function staticcallNoReturn(address target, bytes memory data) internal view returns (bool success) {
        AccountMeta[2] metas = [
            AccountMeta({pubkey: target, is_signer: false, is_writable: false}),
            AccountMeta({pubkey: address(0), is_signer: false, is_writable: false})
        ];
        bytes memory result = target.call{accounts: metas}(data);
        success = result.length == 0;
    }

    /// @dev Performs a Solidity function call using a low level `staticcall` and returns the first 64 bytes of the result
    /// in the scratch space of memory. Useful for functions that return a tuple with two single-word values.
    ///
    /// WARNING: Do not assume that the results are zero if `success` is false. Memory can be already allocated
    /// and this function doesn't zero it out.
    function staticcallReturn64Bytes(
        address target,
        bytes memory data
    ) internal view returns (bool success, bytes32 result1, bytes32 result2) {
        AccountMeta[2] metas = [
            AccountMeta({pubkey: target, is_signer: false, is_writable: false}),
            AccountMeta({pubkey: address(0), is_signer: false, is_writable: false})
        ];
        bytes memory result = target.call{accounts: metas}(data);
        success = result.length >= 64;
        if (success) {
            result1 = abi.decode(result, (bytes32));
            result2 = abi.decode(result[32:], (bytes32));
        } else {
            result1 = bytes32(0);
            result2 = bytes32(0);
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
        size = 0;
    }

    /// @dev Returns a buffer containing the return data from the last call.
    function returnData() internal pure returns (bytes memory result) {
        result = new bytes(0);
    }

    /// @dev Revert with the return data from the last call.
    function bubbleRevert() internal pure {
        revert("bubbleRevert");
    }

    function bubbleRevert(bytes memory returndata) internal pure {
        revert(string(returndata));
    }
}