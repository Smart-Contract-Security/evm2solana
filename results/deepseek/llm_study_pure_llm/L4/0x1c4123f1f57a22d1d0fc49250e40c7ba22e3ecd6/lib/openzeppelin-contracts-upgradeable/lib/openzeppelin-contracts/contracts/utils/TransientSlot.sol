// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library TransientSlot {
    type AddressSlot is bytes32;

    function asAddress(bytes32 slot) internal pure returns (AddressSlot) {
        return AddressSlot.wrap(slot);
    }

    type BooleanSlot is bytes32;

    function asBoolean(bytes32 slot) internal pure returns (BooleanSlot) {
        return BooleanSlot.wrap(slot);
    }

    type Bytes32Slot is bytes32;

    function asBytes32(bytes32 slot) internal pure returns (Bytes32Slot) {
        return Bytes32Slot.wrap(slot);
    }

    type Uint256Slot is bytes32;

    function asUint256(bytes32 slot) internal pure returns (Uint256Slot) {
        return Uint256Slot.wrap(slot);
    }

    type Int256Slot is bytes32;

    function asInt256(bytes32 slot) internal pure returns (Int256Slot) {
        return Int256Slot.wrap(slot);
    }

    function tload(AddressSlot slot) internal view returns (address value) {
        bytes32 raw = tload_raw(AddressSlot.unwrap(slot));
        value = address(uint160(uint256(raw)));
    }

    function tstore(AddressSlot slot, address value) internal {
        tstore_raw(AddressSlot.unwrap(slot), bytes32(uint256(uint160(value))));
    }

    function tload(BooleanSlot slot) internal view returns (bool value) {
        bytes32 raw = tload_raw(BooleanSlot.unwrap(slot));
        value = (raw != bytes32(0));
    }

    function tstore(BooleanSlot slot, bool value) internal {
        tstore_raw(BooleanSlot.unwrap(slot), value ? bytes32(uint256(1)) : bytes32(0));
    }

    function tload(Bytes32Slot slot) internal view returns (bytes32 value) {
        value = tload_raw(Bytes32Slot.unwrap(slot));
    }

    function tstore(Bytes32Slot slot, bytes32 value) internal {
        tstore_raw(Bytes32Slot.unwrap(slot), value);
    }

    function tload(Uint256Slot slot) internal view returns (uint256 value) {
        value = uint256(tload_raw(Uint256Slot.unwrap(slot)));
    }

    function tstore(Uint256Slot slot, uint256 value) internal {
        tstore_raw(Uint256Slot.unwrap(slot), bytes32(value));
    }

    function tload(Int256Slot slot) internal view returns (int256 value) {
        value = int256(uint256(tload_raw(Int256Slot.unwrap(slot))));
    }

    function tstore(Int256Slot slot, int256 value) internal {
        tstore_raw(Int256Slot.unwrap(slot), bytes32(uint256(value)));
    }

    function tload_raw(bytes32 slot) private view returns (bytes32 value) {
        assembly {
            value := tload(slot)
        }
    }

    function tstore_raw(bytes32 slot, bytes32 value) private {
        assembly {
            tstore(slot, value)
        }
    }
}