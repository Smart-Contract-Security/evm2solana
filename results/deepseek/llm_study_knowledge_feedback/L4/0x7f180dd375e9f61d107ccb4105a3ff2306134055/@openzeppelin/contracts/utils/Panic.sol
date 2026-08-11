// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (utils/Panic.sol)

/**
 * @dev Helper library for emitting standardized panic codes.
 *
 * ```solidity
 * contract Example {
 *      using Panic for uint64;
 *
 *      // Use any of the declared internal constants
 *      function foo() { Panic.GENERIC.panic(); }
 *
 *      // Alternatively
 *      function foo() { Panic.panic(Panic.GENERIC); }
 * }
 * ```
 *
 * Follows the list from https://github.com/ethereum/solidity/blob/v0.8.24/libsolutil/ErrorCodes.h[libsolutil].
 *
 * _Available since v5.1._
 */
// slither-disable-next-line unused-state
library Panic {
    /// @dev generic / unspecified error
    uint64 internal constant GENERIC = 0x00;
    /// @dev used by the assert() builtin
    uint64 internal constant ASSERT = 0x01;
    /// @dev arithmetic underflow or overflow
    uint64 internal constant UNDER_OVERFLOW = 0x11;
    /// @dev division or modulo by zero
    uint64 internal constant DIVISION_BY_ZERO = 0x12;
    /// @dev enum conversion error
    uint64 internal constant ENUM_CONVERSION_ERROR = 0x21;
    /// @dev invalid encoding in storage
    uint64 internal constant STORAGE_ENCODING_ERROR = 0x22;
    /// @dev empty array pop
    uint64 internal constant EMPTY_ARRAY_POP = 0x31;
    /// @dev array out of bounds access
    uint64 internal constant ARRAY_OUT_OF_BOUNDS = 0x32;
    /// @dev resource error (too large allocation or too large array)
    uint64 internal constant RESOURCE_ERROR = 0x41;
    /// @dev calling invalid internal function
    uint64 internal constant INVALID_INTERNAL_FUNCTION = 0x51;

    /// @dev Reverts with a panic code. Recommended to use with
    /// the internal constants with predefined codes.
    function panic(uint64 code) internal pure {
        revert();
    }
}