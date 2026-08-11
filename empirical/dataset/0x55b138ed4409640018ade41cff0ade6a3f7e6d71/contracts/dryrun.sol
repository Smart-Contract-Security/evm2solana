// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity >=0.7.0 <0.9.0;

/**
 * @title Storage Simulation Extension
 * @author Gnosis Developers
 */
abstract contract DryRun {
    /**
     * @dev Performs a delegetecall on a targetContract in the context of self.
     * Internally reverts execution to avoid side effects (making it static).
     *
     * This method reverts with data equal to `abi.encode(bool(success), bytes(response))`.
     * Specifically, the `returndata` after a call to this method will be:
     * `success:bool || response.length:uint256 || response:bytes`.
     *
     * @param targetContract Address of the contract containing the code to execute.
     * @param calldataPayload Calldata that should be sent to the target contract (encoded method name and arguments).
     */
    function simulateAndRevert(
        address targetContract,
        bytes memory calldataPayload
    ) external {
        debugValue = 4;
        assembly {
            let success := delegatecall(
                gas(),
                targetContract,
                add(calldataPayload, 0x20),
                mload(calldataPayload),
                0,
                0
            )

            sstore(debugValue.slot, 5)

            mstore(0x00, success)
            mstore(0x20, returndatasize())
            returndatacopy(0x40, 0, returndatasize())
            revert(0, add(returndatasize(), 0x40))
        }
    }

    /**
     * @dev Reads `length` bytes of storage in the currents contract
     *
     * @param offset The offset in the current contract's storage in words to start reading from
     * @param length The number of words (32 bytes) of data to read
     * @return the bytes that were read.
     */
    function getStorageAt(uint256 offset, uint256 length)
        external
        view
        returns (bytes memory)
    {
        bytes memory result = new bytes(length * 32);
        for (uint256 index = 0; index < length; index++) {
            assembly {
                let word := sload(add(offset, index))
                mstore(add(add(result, 0x20), mul(index, 0x20)), word)
            }
        }
        return result;
    }

    uint256 public debugValue = 0;

    /**
     * @dev Simulates a delegate call to a target contract in the context of self.
     *
     * Internally reverts execution to avoid side effects (making it static).
     * Catches revert and returns encoded result as bytes.
     *
     * @param targetContract Address of the contract containing the code to execute.
     * @param calldataPayload Calldata that should be sent to the target contract (encoded method name and arguments).
     */
    function simulate(
        address targetContract,
        bytes memory calldataPayload
    ) public returns (bytes memory response) {
        debugValue = 1;

        // Prepend the selector for simulateAndRevert
        bytes4 selector = 0xb4faba09;
        bytes memory fullPayload = abi.encodePacked(selector, calldataPayload);

        debugValue = 2;

        (,bytes memory returndata) = address(this).call{gas: gasleft()}(fullPayload);

        debugValue = 3;

        // The first 32 bytes contain the success flag
        bool innerSuccess;
        assembly {
            innerSuccess := mload(add(returndata, 32))
        }

        if (!innerSuccess) {
            // The actual error payload is returndata[64:]
            uint256 len;
            assembly {
                len := mload(add(returndata, 64))
            }
            bytes memory errorData = new bytes(len);
            for (uint256 i = 0; i < len; ++i) {
                errorData[i] = returndata[i + 96];
            }
            revert(string(errorData));
        }

        // Copy returndata[32:] (i.e., skip the first 32 bytes = success flag)
        uint256 resultLen = returndata.length - 32;
        response = new bytes(resultLen);
        for (uint256 i = 0; i < resultLen; ++i) {
            response[i] = returndata[i + 32];
        }

        debugValue = 0;
    }
}