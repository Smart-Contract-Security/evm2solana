// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

// This file is auto-generated.

/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
/*                          STRUCTS                           */
/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

/// @dev An enumerable address set in storage.
struct AddressSet {
    mapping(bytes32 => uint256) _data;
}

/// @dev An enumerable bytes32 set in storage.
struct Bytes32Set {
    mapping(bytes32 => uint256) _data;
}

/// @dev An enumerable uint256 set in storage.
struct Uint256Set {
    mapping(bytes32 => uint256) _data;
}

/// @dev An enumerable int256 set in storage.
struct Int256Set {
    mapping(bytes32 => uint256) _data;
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
    error IndexOutOfBounds();

    /// @dev The value cannot be the zero sentinel.
    error ValueIsZeroSentinel();

    /// @dev Cannot accommodate a new unique value with the capacity.
    error ExceedsCapacity();

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
        uint256 rootPacked = _sload(set, rootSlot);
        uint256 n = uint256(uint160(rootPacked));
        result = n >> 1;
        if (n == 0) {
            if (uint256(uint96(rootPacked)) != 0) {
                result = 1;
                if (_sload(set, bytes32(uint256(rootSlot) + result)) != 0) {
                    result = 2;
                    if (_sload(set, bytes32(uint256(rootSlot) + result)) != 0) {
                        result = 3;
                    }
                }
            }
        }
    }

    /// @dev Returns the number of elements in the set.
    function length(Bytes32Set storage set) internal view returns (uint256 result) {
        bytes32 rootSlot = _rootSlot(set);
        uint256 n = _sload(set, bytes32(~uint256(rootSlot)));
        result = n >> 1;
        if (n == 0) {
            if (_sload(set, rootSlot) != 0) {
                result = 1;
                if (_sload(set, bytes32(uint256(rootSlot) + result)) != 0) {
                    result = 2;
                    if (_sload(set, bytes32(uint256(rootSlot) + result)) != 0) {
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
            packed = packed & (packed - 1);
        }
    }

    /// @dev Returns whether `value` is in the set.
    function contains(AddressSet storage set, address value) internal view returns (bool result) {
        bytes32 rootSlot = _rootSlot(set);
        uint256 v = uint256(uint160(value));
        if (v == _ZERO_SENTINEL) {
            revert ValueIsZeroSentinel();
        }
        if (v == 0) {
            v = _ZERO_SENTINEL;
        }
        uint256 rootPacked = _sload(set, rootSlot);
        uint256 n = uint256(uint160(rootPacked));
        if (n == 0) {
            if (uint256(uint96(rootPacked)) == v) {
                return true;
            }
            if (uint256(uint96(_sload(set, bytes32(uint256(rootSlot) + 1)))) == v) {
                return true;
            }
            if (uint256(uint96(_sload(set, bytes32(uint256(rootSlot) + 2)))) == v) {
                return true;
            }
            return false;
        }
        bytes32 positionSlot = keccak256(abi.encodePacked(rootSlot, bytes32(v)));
        return _sload(set, positionSlot) != 0;
    }

    /// @dev Returns whether `value` is in the set.
    function contains(Bytes32Set storage set, bytes32 value) internal view returns (bool result) {
        bytes32 rootSlot = _rootSlot(set);
        uint256 v = uint256(value);
        if (v == _ZERO_SENTINEL) {
            revert ValueIsZeroSentinel();
        }
        if (v == 0) {
            v = _ZERO_SENTINEL;
        }
        uint256 n = _sload(set, bytes32(~uint256(rootSlot)));
        if (n == 0) {
            if (_sload(set, rootSlot) == bytes32(v)) {
                return true;
            }
            if (_sload(set, bytes32(uint256(rootSlot) + 1)) == bytes32(v)) {
                return true;
            }
            if (_sload(set, bytes32(uint256(rootSlot) + 2)) == bytes32(v)) {
                return true;
            }
            return false;
        }
        bytes32 positionSlot = keccak256(abi.encodePacked(rootSlot, bytes32(v)));
        return _sload(set, positionSlot) != 0;
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
        result = (set.data >> value) & 1 == 1;
    }

    /// @dev Adds `value` to the set. Returns whether `value` was not in the set.
    function add(AddressSet storage set, address value) internal returns (bool result) {
        bytes32 rootSlot = _rootSlot(set);
        uint256 v = uint256(uint160(value));
        if (v == _ZERO_SENTINEL) {
            revert ValueIsZeroSentinel();
        }
        if (v == 0) {
            v = _ZERO_SENTINEL;
        }
        uint256 rootPacked = _sload(set, rootSlot);
        uint256 n = uint256(uint160(rootPacked));
        if (n == 0) {
            uint256 v0 = uint256(uint96(rootPacked));
            if (v0 == 0) {
                _sstore(set, rootSlot, bytes32(v << 96));
                return true;
            }
            if (v0 == v) {
                return false;
            }
            uint256 v1 = uint256(uint96(_sload(set, bytes32(uint256(rootSlot) + 1))));
            if (v1 == 0) {
                _sstore(set, bytes32(uint256(rootSlot) + 1), bytes32(v << 96));
                return true;
            }
            if (v1 == v) {
                return false;
            }
            uint256 v2 = uint256(uint96(_sload(set, bytes32(uint256(rootSlot) + 2))));
            if (v2 == 0) {
                _sstore(set, bytes32(uint256(rootSlot) + 2), bytes32(v << 96));
                return true;
            }
            if (v2 == v) {
                return false;
            }
            bytes32 posSlot0 = keccak256(abi.encodePacked(rootSlot, bytes32(v0)));
            _sstore(set, posSlot0, bytes32(uint256(1)));
            bytes32 posSlot1 = keccak256(abi.encodePacked(rootSlot, bytes32(v1)));
            _sstore(set, posSlot1, bytes32(uint256(2)));
            bytes32 posSlot2 = keccak256(abi.encodePacked(rootSlot, bytes32(v2)));
            _sstore(set, posSlot2, bytes32(uint256(3)));
            rootPacked = rootPacked | 7;
            n = 7;
        }
        bytes32 positionSlot = keccak256(abi.encodePacked(rootSlot, bytes32(v)));
        if (_sload(set, positionSlot) == 0) {
            n = n >> 1;
            _sstore(set, positionSlot, bytes32(n + 1));
            if (n == 0) {
                _sstore(set, rootSlot, bytes32((3) | (v << 96)));
                return true;
            }
            _sstore(set, bytes32(uint256(rootSlot) + n), bytes32(v << 96));
            _sstore(set, rootSlot, bytes32(rootPacked + 2));
            return true;
        }
        return false;
    }

    /// @dev Adds `value` to the set. Returns whether `value` was not in the set.
    function add(Bytes32Set storage set, bytes32 value) internal returns (bool result) {
        bytes32 rootSlot = _rootSlot(set);
        uint256 v = uint256(value);
        if (v == _ZERO_SENTINEL) {
            revert ValueIsZeroSentinel();
        }
        if (v == 0) {
            v = _ZERO_SENTINEL;
        }
        uint256 n = _sload(set, bytes32(~uint256(rootSlot)));
        if (n == 0) {
            uint256 v0 = uint256(_sload(set, rootSlot));
            if (v0 == 0) {
                _sstore(set, rootSlot, bytes32(v));
                return true;
            }
            if (v0 == v) {
                return false;
            }
            uint256 v1 = uint256(_sload(set, bytes32(uint256(rootSlot) + 1)));
            if (v1 == 0) {
                _sstore(set, bytes32(uint256(rootSlot) + 1), bytes32(v));
                return true;
            }
            if (v1 == v) {
                return false;
            }
            uint256 v2 = uint256(_sload(set, bytes32(uint256(rootSlot) + 2)));
            if (v2 == 0) {
                _sstore(set, bytes32(uint256(rootSlot) + 2), bytes32(v));
                return true;
            }
            if (v2 == v) {
                return false;
            }
            bytes32 posSlot0 = keccak256(abi.encodePacked(rootSlot, bytes32(v0)));
            _sstore(set, posSlot0, bytes32(uint256(1)));
            bytes32 posSlot1 = keccak256(abi.encodePacked(rootSlot, bytes32(v1)));
            _sstore(set, posSlot1, bytes32(uint256(2)));
            bytes32 posSlot2 = keccak256(abi.encodePacked(rootSlot, bytes32(v2)));
            _sstore(set, posSlot2, bytes32(uint256(3)));
            n = 7;
        }
        bytes32 positionSlot = keccak256(abi.encodePacked(rootSlot, bytes32(v)));
        if (_sload(set, positionSlot) == 0) {
            n = n >> 1;
            _sstore(set, bytes32(uint256(rootSlot) + n), bytes32(v));
            _sstore(set, positionSlot, bytes32(n + 1));
            _sstore(set, bytes32(~uint256(rootSlot)), bytes32((1) | ((n + 1) << 1)));
            return true;
        }
        return false;
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
        uint256 mask = uint256(1) << value;
        result = (set.data & mask) == 0;
        set.data = set.data | mask;
    }

    /// @dev Adds `value` to the set. Returns whether `value` was not in the set.
    /// Reverts if the set grows bigger than the custom on-the-fly capacity `cap`.
    function add(AddressSet storage set, address value, uint256 cap)
        internal
        returns (bool result)
    {
        result = add(set, value);
        if (result && length(set) > cap) revert ExceedsCapacity();
    }

    /// @dev Adds `value` to the set. Returns whether `value` was not in the set.
    /// Reverts if the set grows bigger than the custom on-the-fly capacity `cap`.
    function add(Bytes32Set storage set, bytes32 value, uint256 cap)
        internal
        returns (bool result)
    {
        result = add(set, value);
        if (result && length(set) > cap) revert ExceedsCapacity();
    }

    /// @dev Adds `value` to the set. Returns whether `value` was not in the set.
    /// Reverts if the set grows bigger than the custom on-the-fly capacity `cap`.
    function add(Uint256Set storage set, uint256 value, uint256 cap)
        internal
        returns (bool result)
    {
        result = add(set, value);
        if (result && length(set) > cap) revert ExceedsCapacity();
    }

    /// @dev Adds `value` to the set. Returns whether `value` was not in the set.
    /// Reverts if the set grows bigger than the custom on-the-fly capacity `cap`.
    function add(Int256Set storage set, int256 value, uint256 cap) internal returns (bool result) {
        result = add(set, value);
        if (result && length(set) > cap) revert ExceedsCapacity();
    }

    /// @dev Adds `value` to the set. Returns whether `value` was not in the set.
    /// Reverts if the set grows bigger than the custom on-the-fly capacity `cap`.
    function add(Uint8Set storage set, uint8 value, uint256 cap) internal returns (bool result) {
        result = add(set, value);
        if (result && length(set) > cap) revert ExceedsCapacity();
    }

    /// @dev Removes `value` from the set. Returns whether `value` was in the set.
    function remove(AddressSet storage set, address value) internal returns (bool result) {
        bytes32 rootSlot = _rootSlot(set);
        uint256 v = uint256(uint160(value));
        if (v == _ZERO_SENTINEL) {
            revert ValueIsZeroSentinel();
        }
        if (v == 0) {
            v = _ZERO_SENTINEL;
        }
        uint256 rootPacked = _sload(set, rootSlot);
        uint256 n = uint256(uint160(rootPacked));
        if (n == 0) {
            if (uint256(uint96(rootPacked)) == v) {
                _sstore(set, rootSlot, _sload(set, bytes32(uint256(rootSlot) + 1)));
                _sstore(set, bytes32(uint256(rootSlot) + 1), _sload(set, bytes32(uint256(rootSlot) + 2)));
                _sstore(set, bytes32(uint256(rootSlot) + 2), bytes32(0));
                return true;
            }
            if (uint256(uint96(_sload(set, bytes32(uint256(rootSlot) + 1)))) == v) {
                _sstore(set, bytes32(uint256(rootSlot) + 1), _sload(set, bytes32(uint256(rootSlot) + 2)));
                _sstore(set, bytes32(uint256(rootSlot) + 2), bytes32(0));
                return true;
            }
            if (uint256(uint96(_sload(set, bytes32(uint256(rootSlot) + 2)))) == v) {
                _sstore(set, bytes32(uint256(rootSlot) + 2), bytes32(0));
                return true;
            }
            return false;
        }
        bytes32 positionSlot = keccak256(abi.encodePacked(rootSlot, bytes32(v)));
        uint256 position = _sload(set, positionSlot);
        if (position == 0) {
            return false;
        }
        n = (n >> 1) - 1;
        if (position - 1 != n) {
            uint256 lastValue = uint256(uint96(_sload(set, bytes32(uint256(rootSlot) + n))));
            _sstore(set, bytes32(uint256(rootSlot) + position - 1), bytes32(lastValue << 96));
            bytes32 lastPosSlot = keccak256(abi.encodePacked(rootSlot, bytes32(lastValue)));
            _sstore(set, lastPosSlot, bytes32(position));
        }
        _sstore(set, rootSlot, bytes32((uint256(uint96(rootPacked)) << 96) | ((n << 1) | 1)));
        _sstore(set, positionSlot, bytes32(0));
        return true;
    }

    /// @dev Removes `value` from the set. Returns whether `value` was in the set.
    function remove(Bytes32Set storage set, bytes32 value) internal returns (bool result) {
        bytes32 rootSlot = _rootSlot(set);
        uint256 v = uint256(value);
        if (v == _ZERO_SENTINEL) {
            revert ValueIsZeroSentinel();
        }
        if (v == 0) {
            v = _ZERO_SENTINEL;
        }
        uint256 n = _sload(set, bytes32(~uint256(rootSlot)));
        if (n == 0) {
            if (_sload(set, rootSlot) == bytes32(v)) {
                _sstore(set, rootSlot, _sload(set, bytes32(uint256(rootSlot) + 1)));
                _sstore(set, bytes32(uint256(rootSlot) + 1), _sload(set, bytes32(uint256(rootSlot) + 2)));
                _sstore(set, bytes32(uint256(rootSlot) + 2), bytes32(0));
                return true;
            }
            if (_sload(set, bytes32(uint256(rootSlot) + 1)) == bytes32(v)) {
                _sstore(set, bytes32(uint256(rootSlot) + 1), _sload(set, bytes32(uint256(rootSlot) + 2)));
                _sstore(set, bytes32(uint256(rootSlot) + 2), bytes32(0));
                return true;
            }
            if (_sload(set, bytes32(uint256(rootSlot) + 2)) == bytes32(v)) {
                _sstore(set, bytes32(uint256(rootSlot) + 2), bytes32(0));
                return true;
            }
            return false;
        }
        bytes32 positionSlot = keccak256(abi.encodePacked(rootSlot, bytes32(v)));
        uint256 position = _sload(set, positionSlot);
        if (position == 0) {
            return false;
        }
        n = (n >> 1) - 1;
        if (position - 1 != n) {
            bytes32 lastValue = _sload(set, bytes32(uint256(rootSlot) + n));
            _sstore(set, bytes32(uint256(rootSlot) + position - 1), lastValue);
            bytes32 lastPosSlot = keccak256(abi.encodePacked(rootSlot, lastValue));
            _sstore(set, lastPosSlot, bytes32(position));
        }
        _sstore(set, bytes32(~uint256(rootSlot)), bytes32((n << 1) | 1));
        _sstore(set, positionSlot, bytes32(0));
        return true;
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
        uint256 mask = uint256(1) << value;
        result = (set.data & mask) != 0;
        set.data = set.data & ~mask;
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
        uint256 rootPacked = _sload(set, rootSlot);
        uint256 n = uint256(uint160(rootPacked));
        if (n == 0) {
            uint256 v0 = uint256(uint96(rootPacked));
            if (v0 != 0) {
                n = 1;
                uint256 v1 = uint256(uint96(_sload(set, bytes32(uint256(rootSlot) + 1))));
                if (v1 != 0) {
                    n = 2;
                    uint256 v2 = uint256(uint96(_sload(set, bytes32(uint256(rootSlot) + 2))));
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
            if (uint256(uint160(rootPacked)) == 0) {
                for (uint256 i = 0; i < n; i++) {
                    uint256 v = uint256(uint96(_sload(set, bytes32(uint256(rootSlot) + i))));
                    result[i] = address(uint160(v == _ZERO_SENTINEL ? 0 : v));
                }
            } else {
                for (uint256 i = 0; i < n; i++) {
                    uint256 v = uint256(uint96(_sload(set, bytes32(uint256(rootSlot) + i))));
                    result[i] = address(uint160(v == _ZERO_SENTINEL ? 0 : v));
                }
            }
        }
    }

    /// @dev Returns all of the values in the set.
    /// Note: This can consume more gas than the block gas limit for large sets.
    function values(Bytes32Set storage set) internal view returns (bytes32[] memory result) {
        bytes32 rootSlot = _rootSlot(set);
        uint256 n = _sload(set, bytes32(~uint256(rootSlot)));
        if (n == 0) {
            if (_sload(set, rootSlot) != 0) {
                n = 1;
                if (_sload(set, bytes32(uint256(rootSlot) + 1)) != 0) {
                    n = 2;
                    if (_sload(set, bytes32(uint256(rootSlot) + 2)) != 0) {
                        n = 3;
                    }
                }
            }
        } else {
            n = n >> 1;
        }
        result = new bytes32[](n);
        for (uint256 i = 0; i < n; i++) {
            bytes32 v = _sload(set, bytes32(uint256(rootSlot) + i));
            result[i] = (uint256(v) == _ZERO_SENTINEL) ? bytes32(0) : v;
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
            temp = temp & (temp - 1);
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
        if (i >= length(set)) revert IndexOutOfBounds();
        bytes32 rootSlot = _rootSlot(set);
        uint256 v = uint256(uint96(_sload(set, bytes32(uint256(rootSlot) + i))));
        result = address(uint160(v == _ZERO_SENTINEL ? 0 : v));
    }

    /// @dev Returns the element at index `i` in the set. Reverts if `i` is out-of-bounds.
    function at(Bytes32Set storage set, uint256 i) internal view returns (bytes32 result) {
        if (i >= length(set)) revert IndexOutOfBounds();
        bytes32 rootSlot = _rootSlot(set);
        result = _sload(set, bytes32(uint256(rootSlot) + i));
        if (uint256(result) == _ZERO_SENTINEL) {
            result = bytes32(0);
        }
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
        revert IndexOutOfBounds();
    }

    /// @dev Returns the index of `value`. Returns `NOT_FOUND` if the value does not exist.
    function indexOf(AddressSet storage set, address value)
        internal
        view
        returns (uint256 result)
    {
        result = NOT_FOUND;
        uint256 v = uint256(uint160(value));
        if (v == _ZERO_SENTINEL) return result;
        bytes32 rootSlot = _rootSlot(set);
        if (v == 0) {
            v = _ZERO_SENTINEL;
        }
        uint256 rootPacked = _sload(set, rootSlot);
        uint256 n = uint256(uint160(rootPacked));
        if (n == 0) {
            if (uint256(uint96(rootPacked)) == v) return 0;
            if (uint256(uint96(_sload(set, bytes32(uint256(rootSlot) + 1)))) == v) return 1;
            if (uint256(uint96(_sload(set, bytes32(uint256(rootSlot) + 2)))) == v) return 2;
            return NOT_FOUND;
        }
        bytes32 positionSlot = keccak256(abi.encodePacked(rootSlot, bytes32(v)));
        uint256 pos = _sload(set, positionSlot);
        if (pos == 0) return NOT_FOUND;
        return pos - 1;
    }

    /// @dev Returns the index of `value`. Returns `NOT_FOUND` if the value does not exist.
    function indexOf(Bytes32Set storage set, bytes32 value)
        internal
        view
        returns (uint256 result)
    {
        result = NOT_FOUND;
        uint256 v = uint256(value);
        if (v == _ZERO_SENTINEL) return result;
        bytes32 rootSlot = _rootSlot(set);
        if (v == 0) {
            v = _ZERO_SENTINEL;
        }
        uint256 n = _sload(set, bytes32(~uint256(rootSlot)));
        if (n == 0) {
            if (_sload(set, rootSlot) == bytes32(v)) return 0;
            if (_sload(set, bytes32(uint256(rootSlot) + 1)) == bytes32(v)) return 1;
            if (_sload(set, bytes32(uint256(rootSlot) + 2)) == bytes32(v)) return 2;
            return NOT_FOUND;
        }
        bytes32 positionSlot = keccak256(abi.encodePacked(rootSlot, bytes32(v)));
        uint256 pos = _sload(set, positionSlot);
        if (pos == 0) return NOT_FOUND;
        return pos - 1;
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
        uint256 packed = set.data;
        uint256 mask = uint256(1) << value;
        if ((packed & mask) == 0) {
            return NOT_FOUND;
        }
        result = 0;
        uint256 p = packed & (mask - 1);
        while (p != 0) {
            p = p & (p - 1);
            result++;
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PRIVATE HELPERS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Returns the root slot.
    function _rootSlot(AddressSet storage s) private pure returns (bytes32 r) {
        uint256 slot;
        assembly {
            slot := s.slot
        }
        r = keccak256(abi.encodePacked(_ENUMERABLE_ADDRESS_SET_SLOT_SEED, slot));
    }

    /// @dev Returns the root slot.
    function _rootSlot(Bytes32Set storage s) private pure returns (bytes32 r) {
        uint256 slot;
        assembly {
            slot := s.slot
        }
        r = keccak256(abi.encodePacked(_ENUMERABLE_WORD_SET_SLOT_SEED, slot));
    }

    /// @dev Casts to a Bytes32Set.
    function _toBytes32Set(Uint256Set storage s) private pure returns (Bytes32Set storage c) {
        assembly {
            c.slot := s.slot
        }
    }

    /// @dev Casts to a Bytes32Set.
    function _toBytes32Set(Int256Set storage s) private pure returns (Bytes32Set storage c) {
        assembly {
            c.slot := s.slot
        }
    }

    /// @dev Casts to a uint256 array.
    function _toUints(bytes32[] memory a) private pure returns (uint256[] memory c) {
        assembly {
            c := a
        }
    }

    /// @dev Casts to a int256 array.
    function _toInts(bytes32[] memory a) private pure returns (int256[] memory c) {
        assembly {
            c := a
        }
    }

    /// @dev Reads a storage slot from the set's mapping.
    function _sload(AddressSet storage set, bytes32 slot) private view returns (uint256 value) {
        value = set._data[slot];
    }

    /// @dev Writes a storage slot to the set's mapping.
    function _sstore(AddressSet storage set, bytes32 slot, bytes32 value) private {
        set._data[slot] = uint256(value);
    }

    /// @dev Reads a storage slot from the set's mapping.
    function _sload(Bytes32Set storage set, bytes32 slot) private view returns (uint256 value) {
        value = set._data[slot];
    }

    /// @dev Writes a storage slot to the set's mapping.
    function _sstore(Bytes32Set storage set, bytes32 slot, bytes32 value) private {
        set._data[slot] = uint256(value);
    }
}