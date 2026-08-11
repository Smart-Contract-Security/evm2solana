// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @notice Read and write to persistent storage at a fraction of the cost.
/// @author Solady (https://github.com/Vectorized/solady/blob/main/src/utils/SSTORE2.sol)
/// @author Solmate (https://github.com/transmissions11/solmate/blob/main/src/utils/SSTORE2.sol)
/// @author Saw-mon-and-Natalie (https://github.com/Saw-mon-and-Natalie)
library SSTORE2 {
    error InvalidPointer();
    error ReadOutOfBounds();
    error DeploymentFailed();

    /// @dev We skip the first byte as it's a STOP opcode,
    /// ensuring the contract can't be called.
    uint256 internal constant DATA_OFFSET = 1;

    /// @notice Stores `data` in a contract and returns the address.
    function write(bytes memory data) internal returns (address pointer) {
        // Note: The assembly block below does not expand the memory.
        /// @solidity memory-safe-assembly
        assembly {
            let originalDataLength := mload(data)

            // Add 1 to data size since we are prefixing it with a STOP opcode.
            let dataSize := add(originalDataLength, DATA_OFFSET)

            /**
             * ------------------------------------------------------------------------------+
             * Opcode      | Mnemonic        | Stack                   | Memory              |
             * ------------------------------------------------------------------------------|
             * 61 codeSize | PUSH2 codeSize  | codeSize                |                     |
             * 80          | DUP1            | codeSize codeSize       |                     |
             * 60 0xa      | PUSH1 0xa       | 0xa codeSize codeSize   |                     |
             * 3D          | RETURNDATASIZE  | 0 0xa codeSize codeSize |                     |
             * 39          | CODECOPY        | codeSize                | [0..codeSize): code |
             * 3D          | RETURNDATASZIE  | 0 codeSize              | [0..codeSize): code |
             * F3          | RETURN          |                         | [0..codeSize): code |
             * 00          | STOP            |                         |                     |
             * ------------------------------------------------------------------------------+
             * @dev Prefix the bytecode with a STOP opcode to ensure it cannot be called.
             * Also PUSH2 is used since max contract size cap is 24,576 bytes which is less than 2 ** 16.
             */
            mstore(
                data,
                or(
                    0x61000080600a3d393df300,
                    // Left shift `dataSize` by 64 so that it lines up with the 0000 after PUSH2.
                    shl(0x40, dataSize)
                )
            )

            // Deploy a new contract with the generated creation code.
            pointer := create(0, add(data, 0x15), add(dataSize, 0xa))

            // If `pointer` is zero, revert.
            if iszero(pointer) {
                // Store the function selector of `DeploymentFailed()`.
                mstore(0x00, 0x30116425)
                // Revert with (offset, size).
                revert(0x1c, 0x04)
            }

            // Restore original length of the variable size `data`.
            mstore(data, originalDataLength)
        }
    }

    /// @notice Reads the entire stored data for a given pointer.
    function read(address pointer) internal view returns (bytes memory data) {
        /// @solidity memory-safe-assembly
        assembly {
            // Offset all indices by 1 to skip the prefix.
            let pointerCodesize := extcodesize(pointer)
            if iszero(pointerCodesize) {
                // Store the function selector of `InvalidPointer()`.
                mstore(0x00, 0x11052bb4)
                // Revert with (offset, size).
                revert(0x1c, 0x04)
            }
            // Subtract DATA_OFFSET since we don't want to include the STOP opcode.
            let size := sub(pointerCodesize, DATA_OFFSET)

            // Get a pointer to some free memory.
            data := mload(0x40)

            // Update the free memory pointer to prevent overriding our data.
            // We use and(x, not(31)) as a cheaper equivalent to sub(x, mod(x, 32)).
            // Adding 31 to size and running the result through the logic above ensures
            // the memory pointer remains word-aligned, following the Solidity convention.
            mstore(0x40, add(data, and(add(size, 0x3f), not(0x1f))))

            // Store the size of the data in the first 32 byte chunk of free memory.
            mstore(data, size)

            // Copy the code into memory right after the 32 bytes we used to store the size.
            extcodecopy(pointer, add(data, 0x20), DATA_OFFSET, size)
        }
    }

    /// @notice Reads a byte range [start, end) from the stored data.
    ///         Reverts if end > stored data length.
    function readSlice(address pointer, uint256 start, uint256 end)
        internal view returns (bytes memory data)
    {
        require(end >= start, "SSTORE2: bad slice");
        uint256 sliceSize = end - start;
        /// @solidity memory-safe-assembly
        assembly {
            let pointerCodesize := extcodesize(pointer)
            if iszero(pointerCodesize) {
                mstore(0x00, 0x11052bb4)
                revert(0x1c, 0x04)
            }
            let stored := sub(pointerCodesize, DATA_OFFSET)
            // bounds check: end ≤ stored
            if gt(end, stored) {
                mstore(0x00, 0x84eb0dd1) // ReadOutOfBounds()
                revert(0x1c, 0x04)
            }
            data := mload(0x40)
            mstore(0x40, add(data, and(add(sliceSize, 0x3f), not(0x1f))))
            mstore(data, sliceSize)
            extcodecopy(pointer, add(data, 0x20), add(DATA_OFFSET, start), sliceSize)
        }
    }
}
