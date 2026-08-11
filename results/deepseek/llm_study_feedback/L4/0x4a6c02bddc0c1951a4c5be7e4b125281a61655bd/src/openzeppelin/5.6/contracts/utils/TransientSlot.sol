// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library TransientSlot {
    type AddressSlot is bytes32;
    type BooleanSlot is bytes32;
    type Bytes32Slot is bytes32;
    type Uint256Slot is bytes32;
    type Int256Slot is bytes32;

    function asAddress(bytes32 slot) internal pure returns (AddressSlot) {
        return AddressSlot.wrap(slot);
    }

    function asBoolean(bytes32 slot) internal pure returns (BooleanSlot) {
        return BooleanSlot.wrap(slot);
    }

    function asBytes32(bytes32 slot) internal pure returns (Bytes32Slot) {
        return Bytes32Slot.wrap(slot);
    }

    function asUint256(bytes32 slot) internal pure returns (Uint256Slot) {
        return Uint256Slot.wrap(slot);
    }

    function asInt256(bytes32 slot) internal pure returns (Int256Slot) {
        return Int256Slot.wrap(slot);
    }

    function tloadAddress(AddressSlot slot) internal view returns (address value) {
        bytes32 raw = tload_raw(Bytes32Slot.wrap(AddressSlot.unwrap(slot)));
        value = address(uint160(uint256(raw)));
    }

    function tstoreAddress(AddressSlot slot, address value) internal {
        tstore_raw(Bytes32Slot.wrap(AddressSlot.unwrap(slot)), bytes32(uint256(uint160(value))));
    }

    function tloadBoolean(BooleanSlot slot) internal view returns (bool value) {
        bytes32 raw = tload_raw(Bytes32Slot.wrap(BooleanSlot.unwrap(slot)));
        value = (raw != bytes32(0));
    }

    function tstoreBoolean(BooleanSlot slot, bool value) internal {
        tstore_raw(Bytes32Slot.wrap(BooleanSlot.unwrap(slot)), value ? bytes32(uint256(1)) : bytes32(0));
    }

    function tloadBytes32(Bytes32Slot slot) internal view returns (bytes32 value) {
        value = tload_raw(slot);
    }

    function tstoreBytes32(Bytes32Slot slot, bytes32 value) internal {
        tstore_raw(slot, value);
    }

    function tloadUint256(Uint256Slot slot) internal view returns (uint256 value) {
        bytes32 raw = tload_raw(Bytes32Slot.wrap(Uint256Slot.unwrap(slot)));
        value = uint256(raw);
    }

    function tstoreUint256(Uint256Slot slot, uint256 value) internal {
        tstore_raw(Bytes32Slot.wrap(Uint256Slot.unwrap(slot)), bytes32(value));
    }

    function tloadInt256(Int256Slot slot) internal view returns (int256 value) {
        bytes32 raw = tload_raw(Bytes32Slot.wrap(Int256Slot.unwrap(slot)));
        value = int256(uint256(raw));
    }

    function tstoreInt256(Int256Slot slot, int256 value) internal {
        tstore_raw(Bytes32Slot.wrap(Int256Slot.unwrap(slot)), bytes32(uint256(value)));
    }

    function tload_raw(Bytes32Slot slot) private view returns (bytes32 value) {
        assembly {
            value := tload(slot)
        }
    }

    function tstore_raw(Bytes32Slot slot, bytes32 value) private {
        assembly {
            tstore(slot, value)
        }
    }
}