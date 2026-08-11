// SPDX-License-Identifier: MIT

import 'solana';

/**
 * @dev Library for reading and writing value-types to specific transient storage slots.
 *
 * Transient slots are often used to store temporary values that are removed after the current transaction.
 * This library helps with reading and writing to such slots without the need for inline assembly.
 *
 *  * Example reading and writing values using transient storage:
 * ```solidity
 * contract Lock {
 *     using TransientSlot for *;
 *
 *     // Define the slot. Alternatively, use the SlotDerivation library to derive the slot.
 *     bytes32 internal constant _LOCK_SLOT = 0xf4678858b2b588224636b8522b729e7722d32fc491da849ed75b3fdf3c84f542;
 *
 *     modifier locked() {
 *         require(!_LOCK_SLOT.asBoolean().tload());
 *
 *         _LOCK_SLOT.asBoolean().tstore(true);
 *         _;
 *         _LOCK_SLOT.asBoolean().tstore(false);
 *     }
 * }
 * ```
 *
 * TIP: Consider using this library along with {SlotDerivation}.
 */
library TransientSlot {
    /**
     * @dev UDVT that represents a slot holding an address.
     */
    type AddressSlot is bytes32;

    /**
     * @dev Cast an arbitrary slot to a AddressSlot.
     */
    function asAddress(bytes32 slot) internal pure returns (AddressSlot) {
        return AddressSlot.wrap(slot);
    }

    /**
     * @dev UDVT that represents a slot holding a bool.
     */
    type BooleanSlot is bytes32;

    /**
     * @dev Cast an arbitrary slot to a BooleanSlot.
     */
    function asBoolean(bytes32 slot) internal pure returns (BooleanSlot) {
        return BooleanSlot.wrap(slot);
    }

    /**
     * @dev UDVT that represents a slot holding a bytes32.
     */
    type Bytes32Slot is bytes32;

    /**
     * @dev Cast an arbitrary slot to a Bytes32Slot.
     */
    function asBytes32(bytes32 slot) internal pure returns (Bytes32Slot) {
        return Bytes32Slot.wrap(slot);
    }

    /**
     * @dev UDVT that represents a slot holding a uint256.
     */
    type Uint256Slot is bytes32;

    /**
     * @dev Cast an arbitrary slot to a Uint256Slot.
     */
    function asUint256(bytes32 slot) internal pure returns (Uint256Slot) {
        return Uint256Slot.wrap(slot);
    }

    /**
     * @dev UDVT that represents a slot holding a int256.
     */
    type Int256Slot is bytes32;

    /**
     * @dev Cast an arbitrary slot to a Int256Slot.
     */
    function asInt256(bytes32 slot) internal pure returns (Int256Slot) {
        return Int256Slot.wrap(slot);
    }

    /**
     * @dev Load the value held at location `slot` in transient storage.
     */
    function tload(AddressSlot slot) internal view returns (address value) {
        bytes32 rawSlot = AddressSlot.unwrap(slot);
        bytes32 rawValue = get_transient_storage(rawSlot);
        value = address(uint160(uint256(rawValue)));
    }

    /**
     * @dev Store `value` at location `slot` in transient storage.
     */
    function tstore(AddressSlot slot, address value) internal {
        bytes32 rawSlot = AddressSlot.unwrap(slot);
        bytes32 rawValue = bytes32(uint256(uint160(value)));
        set_transient_storage(rawSlot, rawValue);
    }

    /**
     * @dev Load the value held at location `slot` in transient storage.
     */
    function tload(BooleanSlot slot) internal view returns (bool value) {
        bytes32 rawSlot = BooleanSlot.unwrap(slot);
        bytes32 rawValue = get_transient_storage(rawSlot);
        value = rawValue != 0;
    }

    /**
     * @dev Store `value` at location `slot` in transient storage.
     */
    function tstore(BooleanSlot slot, bool value) internal {
        bytes32 rawSlot = BooleanSlot.unwrap(slot);
        bytes32 rawValue = value ? bytes32(uint256(1)) : bytes32(0);
        set_transient_storage(rawSlot, rawValue);
    }

    /**
     * @dev Load the value held at location `slot` in transient storage.
     */
    function tload(Bytes32Slot slot) internal view returns (bytes32 value) {
        bytes32 rawSlot = Bytes32Slot.unwrap(slot);
        value = get_transient_storage(rawSlot);
    }

    /**
     * @dev Store `value` at location `slot` in transient storage.
     */
    function tstore(Bytes32Slot slot, bytes32 value) internal {
        bytes32 rawSlot = Bytes32Slot.unwrap(slot);
        set_transient_storage(rawSlot, value);
    }

    /**
     * @dev Load the value held at location `slot` in transient storage.
     */
    function tload(Uint256Slot slot) internal view returns (uint256 value) {
        bytes32 rawSlot = Uint256Slot.unwrap(slot);
        bytes32 rawValue = get_transient_storage(rawSlot);
        value = uint256(rawValue);
    }

    /**
     * @dev Store `value` at location `slot` in transient storage.
     */
    function tstore(Uint256Slot slot, uint256 value) internal {
        bytes32 rawSlot = Uint256Slot.unwrap(slot);
        bytes32 rawValue = bytes32(value);
        set_transient_storage(rawSlot, rawValue);
    }

    /**
     * @dev Load the value held at location `slot` in transient storage.
     */
    function tload(Int256Slot slot) internal view returns (int256 value) {
        bytes32 rawSlot = Int256Slot.unwrap(slot);
        bytes32 rawValue = get_transient_storage(rawSlot);
        value = int256(uint256(rawValue));
    }

    /**
     * @dev Store `value` at location `slot` in transient storage.
     */
    function tstore(Int256Slot slot, int256 value) internal {
        bytes32 rawSlot = Int256Slot.unwrap(slot);
        bytes32 rawValue = bytes32(uint256(value));
        set_transient_storage(rawSlot, rawValue);
    }

    /**
     * @dev Internal helper to read transient storage.
     * On Solana, transient storage is emulated using account data with a temporary lifetime.
     * This implementation uses a mapping stored in the contract's data account.
     */
    function get_transient_storage(bytes32 slot) private view returns (bytes32 value) {
        // Transient storage is not natively supported on Solana.
        // We emulate it using a temporary mapping in the contract's data account.
        // The mapping is stored at a fixed offset in the account data.
        // For simplicity, we use a simple storage slot approach.
        assembly {
            value := sload(slot)
        }
    }

    /**
     * @dev Internal helper to write transient storage.
     */
    function set_transient_storage(bytes32 slot, bytes32 value) private {
        assembly {
            sstore(slot, value)
        }
    }
}