// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IBlupetsArtStorage {
    function packed(bytes32 key) external view returns (bytes memory);
}
