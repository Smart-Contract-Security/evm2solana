// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SSTORE2} from "solady/utils/SSTORE2.sol";

/// @title TraitStorage
/// @notice Per-category SSTORE2 blob holding (cumulative weight, offset, weight,
///         name, svg) tuples for every trait variant. One SSTORE2 pointer per
///         category — owner writes the packed blob once, contract reads forever.
///
/// Blob layout (big-endian):
///   [0]              uint8   count
///   [1..3)           uint16  totalWeight
///   for i in [0, count):
///     [3 + i*4 .. 3 + i*4 + 2)   uint16  cumWeight_i   (running sum, inclusive)
///     [3 + i*4 + 2 .. 3 + i*4 + 4) uint16 offset_i     (absolute offset to entry body)
///   entry body @ offset_i:
///     [0]            uint8   weight                    (also encoded in cumWeights)
///     [1]            uint8   nameLen
///     [2 .. 2+nameLen) bytes name
///     [.. ..+2)      uint16  svgLen
///     [.. ..+svgLen) bytes   svg
contract TraitStorage is Ownable {
    /// @dev category id => SSTORE2 pointer (zero = unset)
    mapping(uint8 => address) public pointers;

    bool public frozen;

    event CategorySet(uint8 indexed catId, address pointer, uint256 size);
    event Frozen();

    error AlreadyFrozen();
    error CategoryEmpty();
    error IndexOOB();

    constructor() Ownable(msg.sender) {}

    // ---------- Admin ----------

    function setCategory(uint8 catId, bytes calldata blob) external onlyOwner {
        if (frozen) revert AlreadyFrozen();
        address ptr = SSTORE2.write(blob);
        pointers[catId] = ptr;
        emit CategorySet(catId, ptr, blob.length);
    }

    function freeze() external onlyOwner {
        frozen = true;
        emit Frozen();
    }

    // ---------- Reads ----------

    function categoryCount(uint8 catId) public view returns (uint8) {
        address ptr = pointers[catId];
        if (ptr == address(0)) revert CategoryEmpty();
        return uint8(SSTORE2.read(ptr, 0, 1)[0]);
    }

    function categoryTotalWeight(uint8 catId) public view returns (uint16) {
        address ptr = pointers[catId];
        if (ptr == address(0)) revert CategoryEmpty();
        bytes memory h = SSTORE2.read(ptr, 1, 3);
        return (uint16(uint8(h[0])) << 8) | uint16(uint8(h[1]));
    }

    /// @notice Weighted random pick using `seed`. Returns variant index.
    function pickIndex(uint8 catId, uint256 seed) external view returns (uint8) {
        address ptr = pointers[catId];
        if (ptr == address(0)) revert CategoryEmpty();
        bytes memory header = SSTORE2.read(ptr); // small enough — read whole header region in one go
        uint8 count = uint8(header[0]);
        uint16 total = (uint16(uint8(header[1])) << 8) | uint16(uint8(header[2]));
        uint16 r = uint16(seed % total) + 1; // 1..total inclusive (cumWeights inclusive)
        // linear scan — counts are <= ~10, cheaper than reading individual slices
        for (uint8 i = 0; i < count; ++i) {
            uint256 base = 3 + uint256(i) * 4;
            uint16 cum = (uint16(uint8(header[base])) << 8) | uint16(uint8(header[base + 1]));
            if (r <= cum) return i;
        }
        return count - 1; // unreachable
    }

    function traitOffset(uint8 catId, uint8 idx) public view returns (uint16) {
        address ptr = pointers[catId];
        if (ptr == address(0)) revert CategoryEmpty();
        uint256 hdrStart = 3 + uint256(idx) * 4 + 2;
        bytes memory h = SSTORE2.read(ptr, hdrStart, hdrStart + 2);
        return (uint16(uint8(h[0])) << 8) | uint16(uint8(h[1]));
    }

    function traitName(uint8 catId, uint8 idx) external view returns (string memory) {
        address ptr = pointers[catId];
        uint256 off = traitOffset(catId, idx);
        bytes memory head = SSTORE2.read(ptr, off, off + 2);
        // head[0] = weight (skipped), head[1] = nameLen
        uint256 nameLen = uint8(head[1]);
        return string(SSTORE2.read(ptr, off + 2, off + 2 + nameLen));
    }

    function traitSVG(uint8 catId, uint8 idx) external view returns (string memory) {
        address ptr = pointers[catId];
        uint256 off = traitOffset(catId, idx);
        bytes memory head = SSTORE2.read(ptr, off, off + 2);
        uint256 nameLen = uint8(head[1]);
        uint256 svgLenOff = off + 2 + nameLen;
        bytes memory lenBytes = SSTORE2.read(ptr, svgLenOff, svgLenOff + 2);
        uint256 svgLen = (uint256(uint8(lenBytes[0])) << 8) | uint256(uint8(lenBytes[1]));
        return string(SSTORE2.read(ptr, svgLenOff + 2, svgLenOff + 2 + svgLen));
    }
}
