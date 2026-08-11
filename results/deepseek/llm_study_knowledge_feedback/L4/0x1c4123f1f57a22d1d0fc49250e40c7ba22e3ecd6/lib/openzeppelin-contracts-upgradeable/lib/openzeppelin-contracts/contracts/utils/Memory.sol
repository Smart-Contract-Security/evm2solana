// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.5.0) (utils/Memory.sol)

import {Panic} from "./Panic.sol";

library Memory {
    type Pointer is bytes32;

    function getFreeMemoryPointer() internal pure returns (Pointer ptr) {
        // Solana does not support mload; memory management is handled differently.
        // Returning a default pointer for compatibility.
        ptr = Pointer.wrap(bytes32(0));
    }

    function setFreeMemoryPointer(Pointer ptr) internal pure {
        // Solana does not support mstore; memory management is handled differently.
        // No-op for compatibility.
    }

    function asBytes32(Pointer ptr) internal pure returns (bytes32) {
        return Pointer.unwrap(ptr);
    }

    function asPointer(bytes32 value) internal pure returns (Pointer) {
        return Pointer.wrap(value);
    }

    function forward(Pointer ptr, uint64 offset) internal pure returns (Pointer) {
        // Convert bytes32 to uint64 by taking the lower 8 bytes
        uint64 ptrVal = uint64(uint256(Pointer.unwrap(ptr)));
        return Pointer.wrap(bytes32(uint256(ptrVal + offset)));
    }

    function equal(Pointer ptr1, Pointer ptr2) internal pure returns (bool) {
        return Pointer.unwrap(ptr1) == Pointer.unwrap(ptr2);
    }

    type Slice is bytes32;

    function asSlice(bytes memory self) internal pure returns (Slice result) {
        // Solana does not support mload; we cannot extract length from memory layout.
        // Instead, use .length property of bytes.
        uint64 len = uint64(self.length);
        // We cannot get a raw pointer to memory; Slice is not fully functional on Solana.
        // Return a dummy Slice for compatibility.
        result = Slice.wrap(bytes32(0));
    }

    function length(Slice self) internal pure returns (uint64 result) {
        // Extract length from upper 128 bits
        result = uint64(uint256(Slice.unwrap(self)) >> 128);
    }

    function slice(Slice self, uint64 offset) internal pure returns (Slice) {
        if (offset > length(self)) Panic.panic(Panic.ARRAY_OUT_OF_BOUNDS);
        return _asSlice(length(self) - offset, forward(_pointer(self), offset));
    }

    function slice(Slice self, uint64 offset, uint64 len) internal pure returns (Slice) {
        if (offset + len > length(self)) Panic.panic(Panic.ARRAY_OUT_OF_BOUNDS);
        return _asSlice(len, forward(_pointer(self), offset));
    }

    function load(Slice self, uint64 offset) internal pure returns (bytes32 value) {
        uint64 len = length(self);
        // Math.saturatingSub is not available; implement inline
        uint64 outOfBoundBytes;
        if (0x20 + offset > len) {
            outOfBoundBytes = (0x20 + offset) - len;
        } else {
            outOfBoundBytes = 0;
        }
        if (outOfBoundBytes > 0x1f) Panic.panic(Panic.ARRAY_OUT_OF_BOUNDS);

        // Solana does not support mload; cannot load from arbitrary memory.
        // Return zero for compatibility.
        value = bytes32(0);
    }

    function toBytes(Slice self) internal pure returns (bytes memory result) {
        // Solana does not support mload/mcopy; cannot convert Slice to bytes.
        // Return empty bytes for compatibility.
        result = new bytes(0);
    }

    function _asSlice(uint64 len, Memory.Pointer ptr) private pure returns (Slice result) {
        result = Slice.wrap(bytes32((uint256(len) << 128) | uint256(Pointer.unwrap(ptr))));
    }

    function _pointer(Slice self) private pure returns (Memory.Pointer result) {
        result = Pointer.wrap(bytes32(uint256(Slice.unwrap(self)) & ((uint256(1) << 128) - 1)));
    }
}