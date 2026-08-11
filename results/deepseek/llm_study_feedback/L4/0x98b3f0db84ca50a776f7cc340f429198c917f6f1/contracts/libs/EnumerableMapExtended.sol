// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.6.11;

// ============ External Imports ============
// EnumerableSet is not available in Solang; we implement a minimal replacement inline.

// Minimal Bytes32Set implementation for Solang compatibility
struct Bytes32Set {
    bytes32[] _inner;
    mapping(bytes32 => uint256) _indexes; // 1-based index, 0 means not present
}

library EnumerableSet {
    function length(Bytes32Set storage set) internal view returns (uint256) {
        return set._inner.length;
    }

    function add(Bytes32Set storage set, bytes32 value) internal returns (bool) {
        if (contains(set, value)) {
            return false;
        }
        set._inner.push(value);
        set._indexes[value] = set._inner.length;
        return true;
    }

    function remove(Bytes32Set storage set, bytes32 value) internal returns (bool) {
        uint256 valueIndex = set._indexes[value];
        if (valueIndex == 0) {
            return false;
        }
        uint256 lastIndex = set._inner.length;
        bytes32 lastValue = set._inner[lastIndex - 1];
        // Move the last element to the deleted position
        set._inner[valueIndex - 1] = lastValue;
        set._indexes[lastValue] = valueIndex;
        // Remove the last element
        set._inner.pop();
        delete set._indexes[value];
        return true;
    }

    function contains(Bytes32Set storage set, bytes32 value) internal view returns (bool) {
        return set._indexes[value] != 0;
    }

    function at(Bytes32Set storage set, uint256 index) internal view returns (bytes32) {
        require(index < set._inner.length, "EnumerableSet: index out of bounds");
        return set._inner[index];
    }
}

// extends EnumerableMap with uint256 => bytes32 type
// modelled after https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.8.0/contracts/utils/structs/EnumerableMap.sol
library EnumerableMapExtended {
    using EnumerableSet for Bytes32Set;

    struct UintToBytes32Map {
        Bytes32Set _keys;
        mapping(bytes32 => bytes32) _values;
    }

    // ============ Library Functions ============
    function keys(
        UintToBytes32Map storage map
    ) internal view returns (uint256[] memory _keys) {
        uint256 _length = map._keys.length();
        _keys = new uint256[](_length);
        for (uint256 i = 0; i < _length; i++) {
            _keys[i] = uint256(map._keys.at(i));
        }
    }

    function uint32Keys(
        UintToBytes32Map storage map
    ) internal view returns (uint32[] memory _keys) {
        uint256[] memory uint256keys = keys(map);
        _keys = new uint32[](uint256keys.length);
        for (uint256 i = 0; i < uint256keys.length; i++) {
            _keys[i] = uint32(uint256keys[i]);
        }
    }

    function set(
        UintToBytes32Map storage map,
        uint256 key,
        bytes32 value
    ) internal {
        bytes32 bKey = bytes32(key);
        map._keys.add(bKey);
        map._values[bKey] = value;
    }

    function get(
        UintToBytes32Map storage map,
        uint256 key
    ) internal view returns (bytes32) {
        bytes32 bKey = bytes32(key);
        require(map._keys.contains(bKey), "EnumerableMapExtended: nonexistent key");
        return map._values[bKey];
    }

    function tryGet(
        UintToBytes32Map storage map,
        uint256 key
    ) internal view returns (bool, bytes32) {
        bytes32 bKey = bytes32(key);
        if (map._keys.contains(bKey)) {
            return (true, map._values[bKey]);
        } else {
            return (false, 0);
        }
    }

    function remove(
        UintToBytes32Map storage map,
        uint256 key
    ) internal returns (bool) {
        bytes32 bKey = bytes32(key);
        if (map._keys.contains(bKey)) {
            map._keys.remove(bKey);
            delete map._values[bKey];
            return true;
        }
        return false;
    }

    function contains(
        UintToBytes32Map storage map,
        uint256 key
    ) internal view returns (bool) {
        return map._keys.contains(bytes32(key));
    }

    function length(
        UintToBytes32Map storage map
    ) internal view returns (uint256) {
        return map._keys.length();
    }

    function at(
        UintToBytes32Map storage map,
        uint256 index
    ) internal view returns (uint256, bytes32) {
        bytes32 key = map._keys.at(index);
        bytes32 value = map._values[key];
        return (uint256(key), value);
    }
}