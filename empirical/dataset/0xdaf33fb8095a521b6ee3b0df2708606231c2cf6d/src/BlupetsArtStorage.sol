// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {SSTORE2} from "solady/utils/SSTORE2.sol";
import {IBlupetsArtStorage} from "./IBlupetsArtStorage.sol";

contract BlupetsArtStorage is Ownable, IBlupetsArtStorage {
    mapping(bytes32 => address) public pointers;

    event PackedArtStored(bytes32 indexed key, address indexed pointer, uint256 byteLength);

    error MissingArt();
    error InvalidBatchLength();
    error InvalidAdmin();

    constructor(address admin) {
        if (admin == address(0)) revert InvalidAdmin();
        _transferOwnership(admin);
    }

    function setPacked(bytes32 key, bytes calldata data) external onlyOwner returns (address pointer) {
        pointer = SSTORE2.write(data);
        pointers[key] = pointer;
        emit PackedArtStored(key, pointer, data.length);
    }

    function setPackedBatch(bytes32[] calldata keys, bytes[] calldata values) external onlyOwner {
        if (keys.length == 0 || keys.length != values.length) revert InvalidBatchLength();

        for (uint256 i = 0; i < keys.length; i++) {
            address pointer = SSTORE2.write(values[i]);
            pointers[keys[i]] = pointer;
            emit PackedArtStored(keys[i], pointer, values[i].length);
        }
    }

    function packed(bytes32 key) external view returns (bytes memory) {
        address pointer = pointers[key];
        if (pointer == address(0)) revert MissingArt();
        return SSTORE2.read(pointer);
    }
}
