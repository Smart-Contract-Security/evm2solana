// SPDX-License-Identifier: MIT OR Apache-2.0

// ============ External Imports ============
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

// extends EnumerableMap with uint256 => bytes32 type
// modelled after https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.8.0/contracts/utils/structs/EnumerableMap.sol
library EnumerableMapExtended {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    struct UintToBytes32Map {
        mapping(bytes32 => bytes32) _entries;
        EnumerableSet.Bytes32Set _keys;
    }

    // ============ Library Functions ============
    function keys(
        UintToBytes32Map storage map
    ) internal view returns (uint64[] memory _keys) {
        uint64 _length = uint64(map._keys.length());
        _keys = new uint64[](_length);
        for (uint64 i = 0; i < _length; i++) {
            _keys[i] = uint64(uint256(map._keys.at(uint64(i))));
        }
    }

    function uint32Keys(
        UintToBytes32Map storage map
    ) internal view returns (uint32[] memory _keys) {
        uint64[] memory uint64keys = keys(map);
        _keys = new uint32[](uint64keys.length);
        for (uint64 i = 0; i < uint64keys.length; i++) {
            _keys[i] = uint32(uint64keys[i]);
        }
    }

    function set(
        UintToBytes32Map storage map,
        uint64 key,
        bytes32 value
    ) internal {
        bytes32 bKey = bytes32(uint256(key));
        map._entries[bKey] = value;
        map._keys.add(bKey);
    }

    function get(
        UintToBytes32Map storage map,
        uint64 key
    ) internal view returns (bytes32) {
        bytes32 bKey = bytes32(uint256(key));
        require(map._keys.contains(bKey), "EnumerableMap: nonexistent key");
        return map._entries[bKey];
    }

    function tryGet(
        UintToBytes32Map storage map,
        uint64 key
    ) internal view returns (bool, bytes32) {
        bytes32 bKey = bytes32(uint256(key));
        if (map._keys.contains(bKey)) {
            return (true, map._entries[bKey]);
        }
        return (false, bytes32(0));
    }

    function remove(
        UintToBytes32Map storage map,
        uint64 key
    ) internal returns (bool) {
        bytes32 bKey = bytes32(uint256(key));
        if (map._keys.contains(bKey)) {
            delete map._entries[bKey];
            map._keys.remove(bKey);
            return true;
        }
        return false;
    }

    function contains(
        UintToBytes32Map storage map,
        uint64 key
    ) internal view returns (bool) {
        return map._keys.contains(bytes32(uint256(key)));
    }

    function length(
        UintToBytes32Map storage map
    ) internal view returns (uint64) {
        return uint64(map._keys.length());
    }

    function at(
        UintToBytes32Map storage map,
        uint64 index
    ) internal view returns (uint64, bytes32) {
        bytes32 key = map._keys.at(uint64(index));
        return (uint64(uint256(key)), map._entries[key]);
    }
}