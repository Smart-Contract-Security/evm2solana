import 'solana';

library LowLevelCall {
    /// @dev Performs a Solidity function call using a low level `call` and ignoring the return data.
    function callNoReturn(address target, bytes memory data) internal returns (bool success) {
        return callNoReturn(target, 0, data);
    }

    /// @dev Same as {callNoReturn-address-bytes}, but allows specifying the value to be sent in the call.
    function callNoReturn(address target, uint64 value, bytes memory data) internal returns (bool success) {
        (success, ) = target.call{accounts: []}(data);
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
        return callReturn64Bytes(target, 0, data);
    }

    /// @dev Same as {callReturn64Bytes-address-bytes}, but allows specifying the value to be sent in the call.
    function callReturn64Bytes(
        address target,
        uint64 value,
        bytes memory data
    ) internal returns (bool success, bytes32 result1, bytes32 result2) {
        bytes memory returndata;
        (success, returndata) = target.call{accounts: []}(data);
        if (success && returndata.length >= 64) {
            bytes memory slice1 = new bytes(32);
            bytes memory slice2 = new bytes(32);
            for (uint64 i = 0; i < 32; i++) {
                slice1[i] = returndata[i];
                slice2[i] = returndata[i + 32];
            }
            result1 = abi.decode(slice1, (bytes32));
            result2 = abi.decode(slice2, (bytes32));
        }
    }

    /// @dev Performs a Solidity function call using a low level `staticcall` and ignoring the return data.
    function staticcallNoReturn(address target, bytes memory data) internal view returns (bool success) {
        (success, ) = target.call{accounts: []}(data);
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
        bytes memory returndata;
        (success, returndata) = target.call{accounts: []}(data);
        if (success && returndata.length >= 64) {
            bytes memory slice1 = new bytes(32);
            bytes memory slice2 = new bytes(32);
            for (uint64 i = 0; i < 32; i++) {
                slice1[i] = returndata[i];
                slice2[i] = returndata[i + 32];
            }
            result1 = abi.decode(slice1, (bytes32));
            result2 = abi.decode(slice2, (bytes32));
        }
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
        revert();
    }

    function bubbleRevert(bytes memory returndata) internal pure {
        revert();
    }
}