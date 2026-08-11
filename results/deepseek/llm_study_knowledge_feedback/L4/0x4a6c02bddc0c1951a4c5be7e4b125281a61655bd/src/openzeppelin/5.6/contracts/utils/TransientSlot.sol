// SPDX-License-Identifier: MIT

import 'solana';

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

    function tloadAddress(AddressSlot slot) internal pure returns (address value) {
        value = address(uint160(uint256(AddressSlot.unwrap(slot))));
    }

    function tstoreAddress(AddressSlot slot, address value) internal pure returns (AddressSlot) {
        return AddressSlot.wrap(bytes32(uint256(uint160(value))));
    }

    function tloadBoolean(BooleanSlot slot) internal pure returns (bool value) {
        value = BooleanSlot.unwrap(slot) != bytes32(0);
    }

    function tstoreBoolean(BooleanSlot slot, bool value) internal pure returns (BooleanSlot) {
        return value ? BooleanSlot.wrap(bytes32(uint256(1))) : BooleanSlot.wrap(bytes32(0));
    }

    function tloadBytes32(Bytes32Slot slot) internal pure returns (bytes32 value) {
        value = Bytes32Slot.unwrap(slot);
    }

    function tstoreBytes32(Bytes32Slot slot, bytes32 value) internal pure returns (Bytes32Slot) {
        return Bytes32Slot.wrap(value);
    }

    function tloadUint256(Uint256Slot slot) internal pure returns (uint256 value) {
        value = uint256(Uint256Slot.unwrap(slot));
    }

    function tstoreUint256(Uint256Slot slot, uint256 value) internal pure returns (Uint256Slot) {
        return Uint256Slot.wrap(bytes32(value));
    }

    function tloadInt256(Int256Slot slot) internal pure returns (int256 value) {
        value = int256(uint256(Int256Slot.unwrap(slot)));
    }

    function tstoreInt256(Int256Slot slot, int256 value) internal pure returns (Int256Slot) {
        return Int256Slot.wrap(bytes32(uint256(value)));
    }
}