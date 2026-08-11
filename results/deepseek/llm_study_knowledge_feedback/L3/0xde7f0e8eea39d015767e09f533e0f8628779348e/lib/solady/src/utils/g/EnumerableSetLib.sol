// SPDX-License-Identifier: MIT

// This file is auto-generated.

/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
/*                          STRUCTS                           */
/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

/// @dev An enumerable address set in storage.
struct AddressSet {
    bytes32 _slot;
}

/// @dev An enumerable bytes32 set in storage.
struct Bytes32Set {
    bytes32 _slot;
}

/// @dev An enumerable uint256 set in storage.
struct Uint256Set {
    bytes32 _slot;
}

/// @dev An enumerable int256 set in storage.
struct Int256Set {
    bytes32 _slot;
}

/// @dev An enumerable uint8 set in storage. Useful for enums.
struct Uint8Set {
    uint256 data;
}

using EnumerableSetLib for AddressSet global;
using EnumerableSetLib for Bytes32Set global;
using EnumerableSetLib for Uint256Set global;
using EnumerableSetLib for Int256Set global;
using EnumerableSetLib for Uint8Set global;

/// @notice Library for managing enumerable sets in storage.
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/utils/g/EnumerableSetLib.sol)
///
/// @dev Note:
/// In many applications, the number of elements in an enumerable set is small.
/// This enumerable set implementation avoids storing the length and indices
/// for up to 3 elements. Once the length exceeds 3 for the first time, the length
/// and indices will be initialized. The amortized cost of adding elements is O(1).
///
/// The AddressSet implementation packs the length with the 0th entry.
///
/// All enumerable sets except Uint8Set use a pop and swap mechanism to remove elements.
/// This means that the iteration order of elements can change between element removals.
library EnumerableSetLib {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The index must be less than the length.
    // error IndexOutOfBounds();
    // Solana: custom errors not supported, using revert with string

    /// @dev The value cannot be the zero sentinel.
    // error ValueIsZeroSentinel();
    // Solana: custom errors not supported, using revert with string

    /// @dev Cannot accommodate a new unique value with the capacity.
    // error ExceedsCapacity();
    // Solana: custom errors not supported, using revert with string

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The index to represent a value that does not exist.
    uint256 internal constant NOT_FOUND = type(uint256).max;

    /// @dev A sentinel value to denote the zero value in storage.
    /// No elements can be equal to this value.
    /// `uint72(bytes9(keccak256(bytes("_ZERO_SENTINEL"))))`.
    uint256 private constant _ZERO_SENTINEL = 0xfbb67fda52d4bfb8bf;

    /// @dev The storage layout is given by:
    /// ```
    ///     mstore(0x04, _ENUMERABLE_ADDRESS_SET_SLOT_SEED)
    ///     mstore(0x00, set.slot)
    ///     let rootSlot := keccak256(0x00, 0x24)
    ///     mstore(0x20, rootSlot)
    ///     mstore(0x00, shr(96, shl(96, value)))
    ///     let positionSlot := keccak256(0x00, 0x40)
    ///     let valueSlot := add(rootSlot, sload(positionSlot))
    ///     let valueInStorage := shr(96, sload(valueSlot))
    ///     let lazyLength := shr(160, shl(160, sload(rootSlot)))
    /// ```
    uint256 private constant _ENUMERABLE_ADDRESS_SET_SLOT_SEED = 0x978aab92;

    /// @dev The storage layout is given by:
    /// ```
    ///     mstore(0x04, _ENUMERABLE_WORD_SET_SLOT_SEED)
    ///     mstore(0x00, set.slot)
    ///     let rootSlot := keccak256(0x00, 0x24)
    ///     mstore(0x20, rootSlot)
    ///     mstore(0x00, value)
    ///     let positionSlot := keccak256(0x00, 0x40)
    ///     let valueSlot := add(rootSlot, sload(positionSlot))
    ///     let valueInStorage := sload(valueSlot)
    ///     let lazyLength := sload(not(rootSlot))
    /// ```
    uint256 private constant _ENUMERABLE_WORD_SET_SLOT_SEED = 0x18fb5864;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     GETTERS / SETTERS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Returns the number of elements in the set.
    function length(AddressSet storage set) internal view returns (uint256 result) {
        bytes32 rootSlot = _rootSlot(set);
        uint256 rootPacked = uint256(_sload(rootSlot));
        uint256 n = rootPacked & 0x0000000000000000000000000000000000000000ffffffffffffffffffff;
        result = n >> 1;
        if (n == 0) {
            if ((rootPacked >> 96) != 0) {
                result = 1;
                if (uint256(_sload(bytes32(uint256(rootSlot) + result))) != 0) {
                    result = 2;
                    if (uint256(_sload(bytes32(uint256(rootSlot) + result))) != 0) {
                        result = 3;
                    }
                }
            }
        }
    }

    /// @dev Returns the number of elements in the set.
    function length(Bytes32Set storage set) internal view returns (uint256 result) {
        bytes32 rootSlot = _rootSlot(set);
        uint256 n = uint256(_sload(~rootSlot));
        result = n >> 1;
        if (n == 0) {
            if (uint256(_sload(rootSlot)) != 0) {
                result = 1;
                if (uint256(_sload(bytes32(uint256(rootSlot) + result))) != 0) {
                    result = 2;
                    if (uint256(_sload(bytes32(uint256(rootSlot) + result))) != 0) {
                        result = 3;
                    }
                }
            }
        }
    }

    /// @dev Returns the number of elements in the set.
    function length(Uint256Set storage set) internal view returns (uint256 result) {
        result = length(_toBytes32Set(set));
    }

    /// @dev Returns the number of elements in the set.
    function length(Int256Set storage set) internal view returns (uint256 result) {
        result = length(_toBytes32Set(set));
    }

    /// @dev Returns the number of elements in the set.
    function length(Uint8Set storage set) internal view returns (uint256 result) {
        uint256 packed = set.data;
        while (packed != 0) {
            result += 1;
            packed = packed ^ (packed & (~packed + 1));
        }
    }

    /// @dev Returns whether `value` is in the set.
    function contains(AddressSet storage set, address value) internal view returns (bool result) {
        bytes32 rootSlot = _rootSlot(set);
        uint256 v = uint256(uint160(value));
        if (v == _ZERO_SENTINEL) {
            revert("ValueIsZeroSentinel");
        }
        if (v == 0) { v = _ZERO_SENTINEL; }
        uint256 rootPacked = uint256(_sload(rootSlot));
        uint256 n = rootPacked & 0x0000000000000000000000000000000000000000ffffffffffffffffffff;
        if (n == 0) {
            result = true;
            if ((rootPacked >> 96) == v) return result;
            if ((uint256(_sload(bytes32(uint256(rootSlot) + 1))) >> 96) == v) return result;
            if ((uint256(_sload(bytes32(uint256(rootSlot) + 2))) >> 96) == v) return result;
            result = false;
        } else {
            bytes32 positionSlot = keccak256(abi.encodePacked(v, rootSlot));
            result = uint256(_sload(positionSlot)) != 0;
        }
    }

    /// @dev Returns whether `value` is in the set.
    function contains(Bytes32Set storage set, bytes32 value) internal view returns (bool result) {
        bytes32 rootSlot = _rootSlot(set);
        uint256 v = uint256(value);
        if (v == _ZERO_SENTINEL) {
            revert("ValueIsZeroSentinel");
        }
        if (v == 0) { v = _ZERO_SENTINEL; }
        uint256 n = uint256(_sload(~rootSlot));
        if (n == 0) {
            result = true;
            if (uint256(_sload(rootSlot)) == v) return result;
            if (uint256(_sload(bytes32(uint256(rootSlot) + 1))) == v) return result;
            if (uint256(_sload(bytes32(uint256(rootSlot) + 2))) == v) return result;
            result = false;
        } else {
            bytes32 positionSlot = keccak256(abi.encodePacked(v, rootSlot));
            result = uint256(_sload(positionSlot)) != 0;
        }
    }

    /// @dev Returns whether `value` is in the set.
    function contains(Uint256Set storage set, uint256 value) internal view returns (bool result) {
        result = contains(_toBytes32Set(set), bytes32(value));
    }

    /// @dev Returns whether `value` is in the set.
    function contains(Int256Set storage set, int256 value) internal view returns (bool result) {
        result = contains(_toBytes32Set(set), bytes32(uint256(value)));
    }

    /// @dev Returns whether `value` is in the set.
    function contains(Uint8Set storage set, uint8 value) internal view returns (bool result) {
        result = (set.data >> (value & 0xff)) & 1 == 1;
    }

    /// @dev Adds `value` to the set. Returns whether `value` was not in the set.
    function add(AddressSet storage set, address value) internal returns (bool result) {
        bytes32 rootSlot = _rootSlot(set);
        uint256 v = uint256(uint160(value));
        if (v == _ZERO_SENTINEL) {
            revert("ValueIsZeroSentinel");
        }
        if (v == 0) { v = _ZERO_SENTINEL; }
        uint256 rootPacked = uint256(_sload(rootSlot));
        uint256 n = rootPacked & 0x0000000000000000000000000000000000000000ffffffffffffffffffff;
        if (n == 0) {
            uint256 v0 = rootPacked >> 96;
            if (v0 == 0) {
                _sstore(rootSlot, bytes32(v << 96));
                result = true;
                return result;
            }
            if (v0 == v) return result;
            uint256 v1 = uint256(_sload(bytes32(uint256(rootSlot) + 1))) >> 96;
            if (v1 == 0) {
                _sstore(bytes32(uint256(rootSlot) + 1), bytes32(v << 96));
                result = true;
                return result;
            }
            if (v1 == v) return result;
            uint256 v2 = uint256(_sload(bytes32(uint256(rootSlot) + 2))) >> 96;
            if (v2 == 0) {
                _sstore(bytes32(uint256(rootSlot) + 2), bytes32(v << 96));
                result = true;
                return result;
            }
            if (v2 == v) return result;
            bytes32 pos0 = keccak256(abi.encodePacked(v0, rootSlot));
            _sstore(pos0, bytes32(uint256(1)));
            bytes32 pos1 = keccak256(abi.encodePacked(v1, rootSlot));
            _sstore(pos1, bytes32(uint256(2)));
            bytes32 pos2 = keccak256(abi.encodePacked(v2, rootSlot));
            _sstore(pos2, bytes32(uint256(3)));
            rootPacked = rootPacked | 7;
            n = 7;
        }
        bytes32 p = keccak256(abi.encodePacked(v, rootSlot));
        if (uint256(_sload(p)) == 0) {
            n = n >> 1;
            result = true;
            _sstore(p, bytes32(n + 1));
            if (n == 0) {
                _sstore(rootSlot, bytes32((3) | (v << 96)));
                return result;
            }
            _sstore(bytes32(uint256(rootSlot) + n), bytes32(v << 96));
            _sstore(rootSlot, bytes32(rootPacked + 2));
        }
    }

    /// @dev Adds `value` to the set. Returns whether `value` was not in the set.
    function add(Bytes32Set storage set, bytes32 value) internal returns (bool result) {
        bytes32 rootSlot = _rootSlot(set);
        uint256 v = uint256(value);
        if (v == _ZERO_SENTINEL) {
            revert("ValueIsZeroSentinel");
        }
        if (v == 0) { v = _ZERO_SENTINEL; }
        uint256 n = uint256(_sload(~rootSlot));
        if (n == 0) {
            uint256 v0 = uint256(_sload(rootSlot));
            if (v0 == 0) {
                _sstore(rootSlot, bytes32(v));
                result = true;
                return result;
            }
            if (v0 == v) return result;
            uint256 v1 = uint256(_sload(bytes32(uint256(rootSlot) + 1)));
            if (v1 == 0) {
                _sstore(bytes32(uint256(rootSlot) + 1), bytes32(v));
                result = true;
                return result;
            }
            if (v1 == v) return result;
            uint256 v2 = uint256(_sload(bytes32(uint256(rootSlot) + 2)));
            if (v2 == 0) {
                _sstore(bytes32(uint256(rootSlot) + 2), bytes32(v));
                result = true;
                return result;
            }
            if (v2 == v) return result;
            bytes32 pos0 = keccak256(abi.encodePacked(v0, rootSlot));
            _sstore(pos0, bytes32(uint256(1)));
            bytes32 pos1 = keccak256(abi.encodePacked(v1, rootSlot));
            _sstore(pos1, bytes32(uint256(2)));
            bytes32 pos2 = keccak256(abi.encodePacked(v2, rootSlot));
            _sstore(pos2, bytes32(uint256(3)));
            n = 7;
        }
        bytes32 p = keccak256(abi.encodePacked(v, rootSlot));
        if (uint256(_sload(p)) == 0) {
            n = n >> 1;
            _sstore(bytes32(uint256(rootSlot) + n), bytes32(v));
            _sstore(p, bytes32(n + 1));
            _sstore(~rootSlot, bytes32(1 | ((n + 1) << 1)));
            result = true;
        }
    }

    /// @dev Adds `value` to the set. Returns whether `value` was not in the set.
    function add(Uint256Set storage set, uint256 value) internal returns (bool result) {
        result = add(_toBytes32Set(set), bytes32(value));
    }

    /// @dev Adds `value` to the set. Returns whether `value` was not in the set.
    function add(Int256Set storage set, int256 value) internal returns (bool result) {
        result = add(_toBytes32Set(set), bytes32(uint256(value)));
    }

    /// @dev Adds `value` to the set. Returns whether `value` was not in the set.
    function add(Uint8Set storage set, uint8 value) internal returns (bool result) {
        uint256 prev = set.data;
        uint256 mask = uint256(1) << (value & 0xff);
        set.data = prev | mask;
        result = (prev & mask) == 0;
    }

    /// @dev Adds `value` to the set. Returns whether `value` was not in the set.
    /// Reverts if the set grows bigger than the custom on-the-fly capacity `cap`.
    function add(AddressSet storage set, address value, uint256 cap)
        internal
        returns (bool result)
    {
        result = add(set, value);
        if (result && length(set) > cap) revert("ExceedsCapacity");
    }

    /// @dev Adds `value` to the set. Returns whether `value` was not in the set.
    /// Reverts if the set grows bigger than the custom on-the-fly capacity `cap`.
    function add(Bytes32Set storage set, bytes32 value, uint256 cap)
        internal
        returns (bool result)
    {
        result = add(set, value);
        if (result && length(set) > cap) revert("ExceedsCapacity");
    }

    /// @dev Adds `value` to the set. Returns whether `value` was not in the set.
    /// Reverts if the set grows bigger than the custom on-the-fly capacity `cap`.
    function add(Uint256Set storage set, uint256 value, uint256 cap)
        internal
        returns (bool result)
    {
        result = add(set, value);
        if (result && length(set) > cap) revert("ExceedsCapacity");
    }

    /// @dev Adds `value` to the set. Returns whether `value` was not in the set.
    /// Reverts if the set grows bigger than the custom on-the-fly capacity `cap`.
    function add(Int256Set storage set, int256 value, uint256 cap) internal returns (bool result) {
        result = add(set, value);
        if (result && length(set) > cap) revert("ExceedsCapacity");
    }

    /// @dev Adds `value` to the set. Returns whether `value` was not in the set.
    /// Reverts if the set grows bigger than the custom on-the-fly capacity `cap`.
    function add(Uint8Set storage set, uint8 value, uint256 cap) internal returns (bool result) {
        result = add(set, value);
        if (result && length(set) > cap) revert("ExceedsCapacity");
    }

    /// @dev Removes `value` from the set. Returns whether `value` was in the set.
    function remove(AddressSet storage set, address value) internal returns (bool result) {
        bytes32 rootSlot = _rootSlot(set);
        uint256 v = uint256(uint160(value));
        if (v == _ZERO_SENTINEL) {
            revert("ValueIsZeroSentinel");
        }
        if (v == 0) { v = _ZERO_SENTINEL; }
        uint256 rootPacked = uint256(_sload(rootSlot));
        uint256 n = rootPacked & 0x0000000000000000000000000000000000000000ffffffffffffffffffff;
        if (n == 0) {
            result = true;
            if ((rootPacked >> 96) == v) {
                _sstore(rootSlot, _sload(bytes32(uint256(rootSlot) + 1)));
                _sstore(bytes32(uint256(rootSlot) + 1), _sload(bytes32(uint256(rootSlot) + 2)));
                _sstore(bytes32(uint256(rootSlot) + 2), bytes32(0));
                return result;
            }
            if ((uint256(_sload(bytes32(uint256(rootSlot) + 1))) >> 96) == v) {
                _sstore(bytes32(uint256(rootSlot) + 1), _sload(bytes32(uint256(rootSlot) + 2)));
                _sstore(bytes32(uint256(rootSlot) + 2), bytes32(0));
                return result;
            }
            if ((uint256(_sload(bytes32(uint256(rootSlot) + 2))) >> 96) == v) {
                _sstore(bytes32(uint256(rootSlot) + 2), bytes32(0));
                return result;
            }
            result = false;
            return result;
        }
        bytes32 p = keccak256(abi.encodePacked(v, rootSlot));
        uint256 position = uint256(_sload(p));
        if (position == 0) return result;
        n = (n >> 1) - 1;
        if (position - 1 != n) {
            uint256 lastValue = uint256(_sload(bytes32(uint256(rootSlot) + n))) >> 96;
            _sstore(bytes32(uint256(rootSlot) + position - 1), bytes32(lastValue << 96));
            bytes32 lastPos = keccak256(abi.encodePacked(lastValue, rootSlot));
            _sstore(lastPos, bytes32(position));
        }
        _sstore(rootSlot, bytes32(((rootPacked >> 96) << 96) | ((n << 1) | 1)));
        _sstore(p, bytes32(0));
        result = true;
    }

    /// @dev Removes `value` from the set. Returns whether `value` was in the set.
    function remove(Bytes32Set storage set, bytes32 value) internal returns (bool result) {
        bytes32 rootSlot = _rootSlot(set);
        uint256 v = uint256(value);
        if (v == _ZERO_SENTINEL) {
            revert("ValueIsZeroSentinel");
        }
        if (v == 0) { v = _ZERO_SENTINEL; }
        uint256 n = uint256(_sload(~rootSlot));
        if (n == 0) {
            result = true;
            if (uint256(_sload(rootSlot)) == v) {
                _sstore(rootSlot, _sload(bytes32(uint256(rootSlot) + 1)));
                _sstore(bytes32(uint256(rootSlot) + 1), _sload(bytes32(uint256(rootSlot) + 2)));
                _sstore(bytes32(uint256(rootSlot) + 2), bytes32(0));
                return result;
            }
            if (uint256(_sload(bytes32(uint256(rootSlot) + 1))) == v) {
                _sstore(bytes32(uint256(rootSlot) + 1), _sload(bytes32(uint256(rootSlot) + 2)));
                _sstore(bytes32(uint256(rootSlot) + 2), bytes32(0));
                return result;
            }
            if (uint256(_sload(bytes32(uint256(rootSlot) + 2))) == v) {
                _sstore(bytes32(uint256(rootSlot) + 2), bytes32(0));
                return result;
            }
            result = false;
            return result;
        }
        bytes32 p = keccak256(abi.encodePacked(v, rootSlot));
        uint256 position = uint256(_sload(p));
        if (position == 0) return result;
        n = (n >> 1) - 1;
        if (position - 1 != n) {
            uint256 lastValue = uint256(_sload(bytes32(uint256(rootSlot) + n)));
            _sstore(bytes32(uint256(rootSlot) + position - 1), bytes32(lastValue));
            bytes32 lastPos = keccak256(abi.encodePacked(lastValue, rootSlot));
            _sstore(lastPos, bytes32(position));
        }
        _sstore(~rootSlot, bytes32((n << 1) | 1));
        _sstore(p, bytes32(0));
        result = true;
    }

    /// @dev Removes `value` from the set. Returns whether `value` was in the set.
    function remove(Uint256Set storage set, uint256 value) internal returns (bool result) {
        result = remove(_toBytes32Set(set), bytes32(value));
    }

    /// @dev Removes `value` from the set. Returns whether `value` was in the set.
    function remove(Int256Set storage set, int256 value) internal returns (bool result) {
        result = remove(_toBytes32Set(set), bytes32(uint256(value)));
    }

    /// @dev Removes `value` from the set. Returns whether `value` was in the set.
    function remove(Uint8Set storage set, uint8 value) internal returns (bool result) {
        uint256 prev = set.data;
        uint256 mask = uint256(1) << (value & 0xff);
        set.data = prev & ~mask;
        result = (prev & mask) != 0;
    }

    /// @dev Shorthand for `isAdd ? set.add(value, cap) : set.remove(value)`.
    function update(AddressSet storage set, address value, bool isAdd, uint256 cap)
        internal
        returns (bool)
    {
        return isAdd ? add(set, value, cap) : remove(set, value);
    }

    /// @dev Shorthand for `isAdd ? set.add(value, cap) : set.remove(value)`.
    function update(Bytes32Set storage set, bytes32 value, bool isAdd, uint256 cap)
        internal
        returns (bool)
    {
        return isAdd ? add(set, value, cap) : remove(set, value);
    }

    /// @dev Shorthand for `isAdd ? set.add(value, cap) : set.remove(value)`.
    function update(Uint256Set storage set, uint256 value, bool isAdd, uint256 cap)
        internal
        returns (bool)
    {
        return isAdd ? add(set, value, cap) : remove(set, value);
    }

    /// @dev Shorthand for `isAdd ? set.add(value, cap) : set.remove(value)`.
    function update(Int256Set storage set, int256 value, bool isAdd, uint256 cap)
        internal
        returns (bool)
    {
        return isAdd ? add(set, value, cap) : remove(set, value);
    }

    /// @dev Shorthand for `isAdd ? set.add(value, cap) : set.remove(value)`.
    function update(Uint8Set storage set, uint8 value, bool isAdd, uint256 cap)
        internal
        returns (bool)
    {
        return isAdd ? add(set, value, cap) : remove(set, value);
    }

    /// @dev Returns all of the values in the set.
    /// Note: This can consume more gas than the block gas limit for large sets.
    function values(AddressSet storage set) internal view returns (address[] memory result) {
        bytes32 rootSlot = _rootSlot(set);
        uint256 zs = _ZERO_SENTINEL;
        uint256 rootPacked = uint256(_sload(rootSlot));
        uint256 n = rootPacked & 0x0000000000000000000000000000000000000000ffffffffffffffffffff;
        uint256 v = rootPacked >> 96;
        if (n == 0) {
            if (v != 0) {
                n = 1;
                uint256 v1 = uint256(_sload(bytes32(uint256(rootSlot) + 1))) >> 96;
                if (v1 != 0) {
                    n = 2;
                    uint256 v2 = uint256(_sload(bytes32(uint256(rootSlot) + 2))) >> 96;
                    if (v2 != 0) {
                        n = 3;
                    }
                }
            }
        } else {
            n = n >> 1;
        }
        result = new address[](n);
        if (n > 0) {
            result[0] = address(uint160(v == zs ? 0 : v));
        }
        if (n > 1) {
            uint256 v1 = uint256(_sload(bytes32(uint256(rootSlot) + 1))) >> 96;
            result[1] = address(uint160(v1 == zs ? 0 : v1));
        }
        if (n > 2) {
            uint256 v2 = uint256(_sload(bytes32(uint256(rootSlot) + 2))) >> 96;
            result[2] = address(uint160(v2 == zs ? 0 : v2));
        }
        for (uint256 i = 3; i < n; i++) {
            uint256 vi = uint256(_sload(bytes32(uint256(rootSlot) + i))) >> 96;
            result[i] = address(uint160(vi == zs ? 0 : vi));
        }
    }

    /// @dev Returns all of the values in the set.
    /// Note: This can consume more gas than the block gas limit for large sets.
    function values(Bytes32Set storage set) internal view returns (bytes32[] memory result) {
        bytes32 rootSlot = _rootSlot(set);
        uint256 zs = _ZERO_SENTINEL;
        uint256 n = uint256(_sload(~rootSlot));
        if (n == 0) {
            uint256 v0 = uint256(_sload(rootSlot));
            if (v0 != 0) {
                n = 1;
                if (uint256(_sload(bytes32(uint256(rootSlot) + 1))) != 0) {
                    n = 2;
                    if (uint256(_sload(bytes32(uint256(rootSlot) + 2))) != 0) {
                        n = 3;
                    }
                }
            }
        } else {
            n = n >> 1;
        }
        result = new bytes32[](n);
        for (uint256 i = 0; i < n; i++) {
            uint256 vi = uint256(_sload(bytes32(uint256(rootSlot) + i)));
            result[i] = bytes32(vi == zs ? 0 : vi);
        }
    }

    /// @dev Returns all of the values in the set.
    /// Note: This can consume more gas than the block gas limit for large sets.
    function values(Uint256Set storage set) internal view returns (uint256[] memory result) {
        result = _toUints(values(_toBytes32Set(set)));
    }

    /// @dev Returns all of the values in the set.
    /// Note: This can consume more gas than the block gas limit for large sets.
    function values(Int256Set storage set) internal view returns (int256[] memory result) {
        result = _toInts(values(_toBytes32Set(set)));
    }

    /// @dev Returns all of the values in the set.
    function values(Uint8Set storage set) internal view returns (uint8[] memory result) {
        uint256 packed = set.data;
        uint256 count = 0;
        uint256 temp = packed;
        while (temp != 0) {
            count++;
            temp = temp ^ (temp & (~temp + 1));
        }
        result = new uint8[](count);
        uint256 idx = 0;
        for (uint256 i = 0; i < 256; i++) {
            if ((packed >> i) & 1 == 1) {
                result[idx] = uint8(i);
                idx++;
            }
        }
    }

    /// @dev Returns the element at index `i` in the set. Reverts if `i` is out-of-bounds.
    function at(AddressSet storage set, uint256 i) internal view returns (address result) {
        if (i >= length(set)) revert("IndexOutOfBounds");
        bytes32 rootSlot = _rootSlot(set);
        uint256 v = uint256(_sload(bytes32(uint256(rootSlot) + i))) >> 96;
        result = address(uint160(v == _ZERO_SENTINEL ? 0 : v));
    }

    /// @dev Returns the element at index `i` in the set. Reverts if `i` is out-of-bounds.
    function at(Bytes32Set storage set, uint256 i) internal view returns (bytes32 result) {
        if (i >= length(set)) revert("IndexOutOfBounds");
        bytes32 rootSlot = _rootSlot(set);
        uint256 v = uint256(_sload(bytes32(uint256(rootSlot) + i)));
        result = bytes32(v == _ZERO_SENTINEL ? 0 : v);
    }

    /// @dev Returns the element at index `i` in the set. Reverts if `i` is out-of-bounds.
    function at(Uint256Set storage set, uint256 i) internal view returns (uint256 result) {
        result = uint256(at(_toBytes32Set(set), i));
    }

    /// @dev Returns the element at index `i` in the set. Reverts if `i` is out-of-bounds.
    function at(Int256Set storage set, uint256 i) internal view returns (int256 result) {
        result = int256(uint256(at(_toBytes32Set(set), i)));
    }

    /// @dev Returns the element at index `i` in the set. Reverts if `i` is out-of-bounds.
    function at(Uint8Set storage set, uint256 i) internal view returns (uint8 result) {
        uint256 packed = set.data;
        uint256 count = 0;
        for (uint256 j = 0; j < 256; j++) {
            if ((packed >> j) & 1 == 1) {
                if (count == i) {
                    return uint8(j);
                }
                count++;
            }
        }
        revert("IndexOutOfBounds");
    }

    /// @dev Returns the index of `value`. Returns `NOT_FOUND` if the value does not exist.
    function indexOf(AddressSet storage set, address value)
        internal
        view
        returns (uint256 result)
    {
        result = NOT_FOUND;
        if (uint160(value) == _ZERO_SENTINEL) return result;
        bytes32 rootSlot = _rootSlot(set);
        uint256 v = uint256(uint160(value));
        if (v == 0) { v = _ZERO_SENTINEL; }
        uint256 rootPacked = uint256(_sload(rootSlot));
        uint256 n = rootPacked & 0x0000000000000000000000000000000000000000ffffffffffffffffffff;
        if (n == 0) {
            if ((rootPacked >> 96) == v) return 0;
            if ((uint256(_sload(bytes32(uint256(rootSlot) + 1))) >> 96) == v) return 1;
            if ((uint256(_sload(bytes32(uint256(rootSlot) + 2))) >> 96) == v) return 2;
            return NOT_FOUND;
        }
        bytes32 p = keccak256(abi.encodePacked(v, rootSlot));
        uint256 pos = uint256(_sload(p));
        if (pos == 0) return NOT_FOUND;
        result = pos - 1;
    }

    /// @dev Returns the index of `value`. Returns `NOT_FOUND` if the value does not exist.
    function indexOf(Bytes32Set storage set, bytes32 value)
        internal
        view
        returns (uint256 result)
    {
        result = NOT_FOUND;
        if (uint256(value) == _ZERO_SENTINEL) return result;
        bytes32 rootSlot = _rootSlot(set);
        uint256 v = uint256(value);
        if (v == 0) { v = _ZERO_SENTINEL; }
        uint256 n = uint256(_sload(~rootSlot));
        if (n == 0) {
            if (uint256(_sload(rootSlot)) == v) return 0;
            if (uint256(_sload(bytes32(uint256(rootSlot) + 1))) == v) return 1;
            if (uint256(_sload(bytes32(uint256(rootSlot) + 2))) == v) return 2;
            return NOT_FOUND;
        }
        bytes32 p = keccak256(abi.encodePacked(v, rootSlot));
        uint256 pos = uint256(_sload(p));
        if (pos == 0) return NOT_FOUND;
        result = pos - 1;
    }

    /// @dev Returns the index of `value`. Returns `NOT_FOUND` if the value does not exist.
    function indexOf(Uint256Set storage set, uint256 i) internal view returns (uint256 result) {
        result = indexOf(_toBytes32Set(set), bytes32(i));
    }

    /// @dev Returns the index of `value`. Returns `NOT_FOUND` if the value does not exist.
    function indexOf(Int256Set storage set, int256 i) internal view returns (uint256 result) {
        result = indexOf(_toBytes32Set(set), bytes32(uint256(i)));
    }

    /// @dev Returns the index of `value`. Returns `NOT_FOUND` if the value does not exist.
    function indexOf(Uint8Set storage set, uint8 value) internal view returns (uint256 result) {
        result = NOT_FOUND;
        uint256 packed = set.data;
        uint256 mask = uint256(1) << (value & 0xff);
        if ((packed & mask) != 0) {
            result = 0;
            uint256 p = packed & (mask - 1);
            while (p != 0) {
                p = p ^ (p & (~p + 1));
                result++;
            }
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PRIVATE HELPERS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Returns the root slot.
    function _rootSlot(AddressSet storage s) private pure returns (bytes32 r) {
        r = keccak256(abi.encodePacked(s._slot, _ENUMERABLE_ADDRESS_SET_SLOT_SEED));
    }

    /// @dev Returns the root slot.
    function _rootSlot(Bytes32Set storage s) private pure returns (bytes32 r) {
        r = keccak256(abi.encodePacked(s._slot, _ENUMERABLE_WORD_SET_SLOT_SEED));
    }

    /// @dev Casts to a Bytes32Set.
    function _toBytes32Set(Uint256Set storage s) private pure returns (Bytes32Set storage c) {
        bytes32 slot = s._slot;
        // Solana: no assembly mstore, use direct storage pointer manipulation
        // The storage pointer c is at the same location as s._slot
        // We use a low-level approach: cast the storage reference
        c._slot = slot;
    }

    /// @dev Casts to a Bytes32Set.
    function _toBytes32Set(Int256Set storage s) private pure returns (Bytes32Set storage c) {
        bytes32 slot = s._slot;
        // Solana: no assembly mstore, use direct storage pointer manipulation
        c._slot = slot;
    }

    /// @dev Casts to a uint256 array.
    function _toUints(bytes32[] memory a) private pure returns (uint256[] memory c) {
        // Solana: no assembly, use direct memory reinterpretation
        // bytes32 and uint256 have the same memory layout
        uint256 length = a.length;
        c = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            c[i] = uint256(a[i]);
        }
    }

    /// @dev Casts to a int256 array.
    function _toInts(bytes32[] memory a) private pure returns (int256[] memory c) {
        // Solana: no assembly, use direct memory reinterpretation
        uint256 length = a.length;
        c = new int256[](length);
        for (uint256 i = 0; i < length; i++) {
            c[i] = int256(uint256(a[i]));
        }
    }

    /// @dev Replacement for sload (not available on Solana).
    function _sload(bytes32 slot) private view returns (bytes32 result) {
        // Solana: sload is not available. Use storage reads via inline assembly is not supported.
        // Instead, we use a workaround: read from a mapping-like structure.
        // Since we cannot use assembly sload, we use a storage variable approach.
        // We'll use a dummy mapping to simulate sload.
        // Actually, Solang supports reading storage slots via the storage keyword.
        // We can use a helper contract or simply use the storage variable directly.
        // The simplest approach: use a private mapping as storage backend.
        result = _storageBackend[slot];
    }

    /// @dev Replacement for sstore (not available on Solana).
    function _sstore(bytes32 slot, bytes32 value) private {
        // Solana: sstore is not available. Use storage writes via mapping.
        _storageBackend[slot] = value;
    }

    /// @dev Private mapping used as storage backend to replace sload/sstore.
    /// This mapping is shared across all instances of the library.
    /// Note: This is a workaround. In practice, each contract using this library
    /// will have its own storage layout. The original code used assembly to directly
    /// access storage slots. Since Solang does not support sload/sstore in assembly,
    /// we use a mapping to simulate the same behavior.
    /// WARNING: This changes the storage layout. The original code relied on
    /// raw storage slot manipulation. This adaptation uses a mapping which
    /// may not be compatible with the original storage layout expectations.
    /// For a production port, a complete redesign of the storage layout would be needed.
    mapping(bytes32 => bytes32) private _storageBackend;
}