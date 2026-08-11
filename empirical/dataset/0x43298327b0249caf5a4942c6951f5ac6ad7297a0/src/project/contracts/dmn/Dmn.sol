// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IDmn.sol";
import "../library/IRandomSeedProvider.sol";
import "../library/RandomLib.sol";

/// @notice Native DMN object registry with compact range ownership for large swap mints.
contract Dmn is IDmn {
    using RandomLibrary for Random;

    uint256 internal constant MAX_DMN_ID = 6_000_000;

    mapping(uint256 objectId => uint256 seed) internal _dmns;

    mapping(address owner => uint256 count) internal _counts;
    mapping(address owner => mapping(uint256 index => uint256 objectId)) internal _ownedDmns;
    mapping(address owner => mapping(uint256 objectId => uint256 index)) internal _ownedDmnIndexes;
    mapping(address owner => mapping(uint256 objectId => bool owns)) internal _owns;

    mapping(uint256 index => address user) private _holderList;
    mapping(address user => uint256 index) private _holderListNumbers;

    struct DmnMintRange {
        uint128 start;
        uint128 end;
        uint256 rangeSeed;
    }

    struct OwnedDmnRange {
        uint128 start;
        uint128 end;
    }

    DmnMintRange[] internal _dmnMintRanges;
    mapping(uint256 objectId => bool dead) internal _deadDmns;
    mapping(address owner => OwnedDmnRange[] ranges) internal _ownedDmnRanges;
    mapping(address owner => uint256 count) internal _ownedDmnRangeCounts;

    uint256 internal _dmnsTotalCount;
    uint256 internal _holdersCount;

    IRandomSeedProvider public randomSeedProvider;

    error MaxDmnSupplyExceeded();

    modifier onlyDmnOwner(uint256 objectId) {
        if (!_ownerOwnsDmn(msg.sender, objectId)) revert NotDmnOwner();
        _;
    }

    modifier onlyDmnIndex(address owner, uint256 index) {
        if (index >= OwnerDmnsCount(owner)) revert DmnIndexOutOfRange();
        _;
    }

    function _setRandomSeedProvider(address newRandomSeedProvider) internal {
        randomSeedProvider = IRandomSeedProvider(newRandomSeedProvider);
    }

    function createRandom() internal view returns (Random memory) {
        return Random(randomSeedProvider.randomSeed(), 0);
    }

    function IsHolder(address owner) public view returns (bool) {
        return _holderListNumbers[owner] > 0;
    }

    function DmnsTotalCount() external view returns (uint256) {
        return _dmnsTotalCount;
    }

    function HoldersCount() external view returns (uint256) {
        return _holdersCount;
    }

    function OwnerDmnsCount(address owner) public view returns (uint256) {
        return _counts[owner] + _ownedDmnRangeCounts[owner];
    }

    function OwnerDmn(address owner, uint256 index) external view returns (DmnSeedData memory) {
        if (index >= OwnerDmnsCount(owner)) revert DmnIndexOutOfRange();
        if (index < _counts[owner]) {
            uint256 id = _ownedDmns[owner][index];
            return DmnSeedData({id: id, seed: _dmnSeed(id)});
        }
        uint256 rangeId = _ownedDmnInRanges(owner, index - _counts[owner]);
        return DmnSeedData({id: rangeId, seed: _dmnSeed(rangeId)});
    }

    function OwnerDmnIndex(address owner, uint256 objectId) external view returns (uint256 index) {
        if (_owns[owner][objectId]) return _ownedDmnIndexes[owner][objectId];
        (bool found, uint256 rangeIndex) = _ownedDmnRangeIndex(owner, objectId);
        if (!found) revert NotDmnOwner();
        return _counts[owner] + rangeIndex;
    }

    function OwnerOwns(address owner, uint256 objectId) external view returns (bool) {
        return _ownerOwnsDmn(owner, objectId);
    }

    function Holder(uint256 index) external view returns (address) {
        return _holderList[index];
    }

    function HolderNumber(address owner) external view returns (uint256) {
        return _holderListNumbers[owner];
    }

    function OwnerDmnsPage(address owner, uint256 page, uint256 pageSize)
        external
        view
        override
        returns (DmnSeedData[] memory dmns)
    {
        uint256 count = OwnerDmnsCount(owner);
        if (pageSize == 0) return new DmnSeedData[](0);

        uint256 start = page * pageSize;
        if (start >= count) return new DmnSeedData[](0);

        uint256 end = start + pageSize;
        if (end > count) end = count;

        uint256 len = end - start;
        dmns = new DmnSeedData[](len);
        for (uint256 i = 0; i < len; ++i) {
            if (start + i < _counts[owner]) {
                uint256 id = _ownedDmns[owner][start + i];
                dmns[i] = DmnSeedData({id: id, seed: _dmnSeed(id)});
            } else {
                uint256 rangeId = _ownedDmnInRanges(owner, start + i - _counts[owner]);
                dmns[i] = DmnSeedData({id: rangeId, seed: _dmnSeed(rangeId)});
            }
        }
    }

    function ReorderDmn(address owner, uint256 objectId, uint256 newIndex)
        external
        override
        onlyDmnOwner(objectId)
        onlyDmnIndex(owner, newIndex)
    {
        if (!_owns[owner][objectId] || newIndex >= _counts[owner]) revert DmnIndexOutOfRange();
        uint256 currentIndex = _ownedDmnIndexes[owner][objectId];
        if (newIndex == currentIndex) return;

        if (newIndex < currentIndex) {
            for (uint256 i = currentIndex; i > newIndex; --i) {
                _ownedDmns[owner][i] = _ownedDmns[owner][i - 1];
                _ownedDmnIndexes[owner][_ownedDmns[owner][i]] = i;
            }
        } else {
            for (uint256 i = currentIndex; i < newIndex; ++i) {
                _ownedDmns[owner][i] = _ownedDmns[owner][i + 1];
                _ownedDmnIndexes[owner][_ownedDmns[owner][i]] = i;
            }
        }

        _ownedDmns[owner][newIndex] = objectId;
        _ownedDmnIndexes[owner][objectId] = newIndex;
    }

    function ReorderDmnPair(address owner, uint256 objectId, uint256 newIndex)
        external
        override
        onlyDmnOwner(objectId)
        onlyDmnIndex(owner, newIndex)
    {
        if (!_owns[owner][objectId] || newIndex >= _counts[owner]) revert DmnIndexOutOfRange();
        uint256 currentIndex = _ownedDmnIndexes[owner][objectId];
        if (newIndex == currentIndex) return;

        uint256 otherId = _ownedDmns[owner][newIndex];
        _ownedDmns[owner][newIndex] = objectId;
        _ownedDmns[owner][currentIndex] = otherId;
        _ownedDmnIndexes[owner][objectId] = newIndex;
        _ownedDmnIndexes[owner][otherId] = currentIndex;
    }

    function transferDmn(address to, uint256 objectId) external override onlyDmnOwner(objectId) {
        _transferDmn(msg.sender, to, objectId);
        _afterDmnTransferred(msg.sender, to, objectId);
    }

    function transferDmnsList(address to, uint256[] calldata objectIds) external override {
        uint256 len = objectIds.length;
        if (len == 0) return;

        for (uint256 i = 0; i < len; ++i) {
            if (!_ownerOwnsDmn(msg.sender, objectIds[i])) revert NotDmnOwner();
            _transferDmn(msg.sender, to, objectIds[i]);
        }

        _afterDmnsListTransferred(msg.sender, to, objectIds);
    }

    function _mintDmn(address owner, uint256 seed) internal virtual returns (DmnSeedData memory seedData) {
        seedData = _createDmn(owner, seed);
        emit OnDmnMinted(owner, seedData.id);
    }

    function _mintDmn(address owner, Random memory random) internal virtual returns (DmnSeedData memory seedData) {
        return _mintDmn(owner, random.next());
    }

    function _burnDmn(address owner, uint256 objectId) internal virtual returns (uint256 seed) {
        seed = _deleteDmn(owner, objectId);
        emit OnDmnBurned(owner, objectId);
    }

    function _mintDmnRange(address owner, uint256 qty, uint256 rangeSeed)
        internal
        virtual
        returns (uint256 start, uint256 end)
    {
        if (qty == 0) return (0, 0);
        start = _dmnsTotalCount + 1;
        end = _dmnsTotalCount + qty;
        if (end > MAX_DMN_ID) revert MaxDmnSupplyExceeded();
        if (end > type(uint128).max) revert DmnIndexOutOfRange();
        _dmnsTotalCount = end;

        _dmnMintRanges.push(DmnMintRange({start: uint128(start), end: uint128(end), rangeSeed: rangeSeed}));
        _insertDmnRangeToOwner(owner, uint128(start), uint128(end));
        emit OnDmnRangeMinted(owner, start, end);
    }

    function _transferDmn(address from, address to, uint256 objectId) internal {
        _validateDmnRecipient(to);
        _removeDmnFromOwner(from, objectId);
        _materializeDmn(objectId);
        _insertExistingDmnToOwner(to, objectId);
        emit OnDmnTransfer(from, to, objectId);
    }

    function _insertExistingDmnToOwner(address owner, uint256 objectId) internal {
        _validateDmnRecipient(owner);
        if (_dmnSeed(objectId) == 0) revert NotDmnOwner();
        _ownedDmns[owner][_counts[owner]] = objectId;
        _ownedDmnIndexes[owner][objectId] = _counts[owner];
        _counts[owner]++;
        _owns[owner][objectId] = true;

        if (!IsHolder(owner)) {
            _holderList[_holdersCount] = owner;
            _holderListNumbers[owner] = ++_holdersCount;
        }
    }

    function _removeDmnFromOwner(address owner, uint256 objectId) internal {
        if (!_owns[owner][objectId]) {
            if (!_removeDmnFromOwnerRange(owner, objectId)) revert NotDmnOwner();
            return;
        }

        uint256 idx = _ownedDmnIndexes[owner][objectId];
        uint256 lastIdx = _counts[owner] - 1;

        if (idx != lastIdx) {
            uint256 lastId = _ownedDmns[owner][lastIdx];
            _ownedDmns[owner][idx] = lastId;
            _ownedDmnIndexes[owner][lastId] = idx;
        }

        delete _ownedDmns[owner][lastIdx];
        delete _ownedDmnIndexes[owner][objectId];
        _counts[owner]--;
        _owns[owner][objectId] = false;

        if (_counts[owner] == 0 && _ownedDmnRangeCounts[owner] == 0 && IsHolder(owner)) _removeHolder(owner);
    }

    function _createDmn(address owner, uint256 seed) private returns (DmnSeedData memory seedData) {
        if (_dmnsTotalCount >= MAX_DMN_ID) revert MaxDmnSupplyExceeded();
        uint256 objectId = ++_dmnsTotalCount;
        _dmns[objectId] = seed;
        _insertExistingDmnToOwner(owner, objectId);
        return DmnSeedData({id: objectId, seed: seed});
    }

    function _deleteDmn(address owner, uint256 objectId) private returns (uint256 seed) {
        _removeDmnFromOwner(owner, objectId);
        seed = _dmnSeed(objectId);
        _markDmnDead(uint128(objectId), uint128(objectId));
        delete _dmns[objectId];
    }

    function _dmnSeed(uint256 objectId) internal view returns (uint256 seed) {
        seed = _dmns[objectId];
        if (seed != 0) return seed;
        if (_isDmnDead(objectId)) return 0;
        (bool found, uint256 rangeSeed) = _dmnMintRangeSeed(objectId);
        if (!found) return 0;
        return uint256(keccak256(abi.encodePacked("TEST_DMN_RANGE_SEED_V3", rangeSeed, objectId)));
    }

    function _dmnExists(uint256 objectId) internal view returns (bool) {
        return _dmnSeed(objectId) != 0;
    }

    function _materializeDmn(uint256 objectId) internal returns (uint256 seed) {
        seed = _dmnSeed(objectId);
        if (seed == 0) revert NotDmnOwner();
        if (_dmns[objectId] == 0) _dmns[objectId] = seed;
    }

    function _ownerOwnsDmn(address owner, uint256 objectId) internal view returns (bool) {
        return _owns[owner][objectId] || _ownerOwnsDmnInRange(owner, objectId);
    }

    function _insertDmnRangeToOwner(address owner, uint128 start, uint128 end) internal {
        _validateDmnRecipient(owner);
        _ownedDmnRanges[owner].push(OwnedDmnRange({start: start, end: end}));
        _ownedDmnRangeCounts[owner] += uint256(end) - uint256(start) + 1;

        if (!IsHolder(owner)) {
            _holderList[_holdersCount] = owner;
            _holderListNumbers[owner] = ++_holdersCount;
        }
    }

    function _ownedDmnInRanges(address owner, uint256 rangeIndex) private view returns (uint256 objectId) {
        OwnedDmnRange[] storage ranges = _ownedDmnRanges[owner];
        uint256 cursor = rangeIndex;
        for (uint256 i = 0; i < ranges.length; ++i) {
            uint256 len = uint256(ranges[i].end) - uint256(ranges[i].start) + 1;
            if (cursor < len) return uint256(ranges[i].start) + cursor;
            cursor -= len;
        }
        revert DmnIndexOutOfRange();
    }

    function _ownedDmnRangeIndex(address owner, uint256 objectId)
        private
        view
        returns (bool found, uint256 rangeIndex)
    {
        OwnedDmnRange[] storage ranges = _ownedDmnRanges[owner];
        uint256 cursor;
        for (uint256 i = 0; i < ranges.length; ++i) {
            uint256 len = uint256(ranges[i].end) - uint256(ranges[i].start) + 1;
            if (objectId >= ranges[i].start && objectId <= ranges[i].end) {
                return (true, cursor + objectId - uint256(ranges[i].start));
            }
            cursor += len;
        }
    }

    function _ownerOwnsDmnInRange(address owner, uint256 objectId) private view returns (bool) {
        (bool found,) = _ownedDmnRangeIndex(owner, objectId);
        return found;
    }

    function _removeDmnFromOwnerRange(address owner, uint256 objectId) private returns (bool) {
        OwnedDmnRange[] storage ranges = _ownedDmnRanges[owner];
        for (uint256 i = 0; i < ranges.length; ++i) {
            OwnedDmnRange memory range = ranges[i];
            if (objectId < range.start || objectId > range.end) continue;

            uint256 len = uint256(range.end) - uint256(range.start) + 1;
            _ownedDmnRangeCounts[owner] -= 1;

            if (len == 1) {
                ranges[i] = ranges[ranges.length - 1];
                ranges.pop();
            } else if (objectId == range.start) {
                ranges[i].start = uint128(objectId + 1);
            } else if (objectId == range.end) {
                ranges[i].end = uint128(objectId - 1);
            } else {
                ranges[i].end = uint128(objectId - 1);
                ranges.push(OwnedDmnRange({start: uint128(objectId + 1), end: range.end}));
            }

            if (_counts[owner] == 0 && _ownedDmnRangeCounts[owner] == 0 && IsHolder(owner)) _removeHolder(owner);
            return true;
        }
        return false;
    }

    function _dmnMintRangeSeed(uint256 objectId) private view returns (bool found, uint256 rangeSeed) {
        uint256 low;
        uint256 high = _dmnMintRanges.length;
        while (low < high) {
            uint256 mid = (low + high) / 2;
            DmnMintRange storage range = _dmnMintRanges[mid];
            if (objectId < range.start) {
                high = mid;
            } else if (objectId > range.end) {
                low = mid + 1;
            } else {
                return (true, range.rangeSeed);
            }
        }
    }

    function _markDmnDead(uint128 start, uint128 end) internal {
        for (uint256 objectId = start; objectId <= end; ++objectId) {
            _deadDmns[objectId] = true;
        }
    }

    function _isDmnDead(uint256 objectId) private view returns (bool) {
        return _deadDmns[objectId];
    }

    function _removeHolder(address owner) private {
        uint256 holderNumber = _holderListNumbers[owner];
        if (holderNumber == 0) return;

        uint256 index = holderNumber - 1;
        uint256 lastIndex = _holdersCount - 1;
        if (index != lastIndex) {
            address lastHolder = _holderList[lastIndex];
            _holderList[index] = lastHolder;
            _holderListNumbers[lastHolder] = holderNumber;
        }

        delete _holderList[lastIndex];
        delete _holderListNumbers[owner];
        _holdersCount--;
    }

    function _validateDmnRecipient(address to) internal view virtual {
        if (to == address(0)) revert NotDmnOwner();
    }

    function _afterDmnTransferred(address from, address to, uint256 objectId) internal virtual {}

    function _afterDmnsListTransferred(address from, address to, uint256[] calldata objectIds) internal virtual {}
}
