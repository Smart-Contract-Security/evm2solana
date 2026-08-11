// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IBlupetsDescriptor {
    function lineageName(uint8 stage, uint8 lineage) external view returns (string memory);
    function formName(uint8 stage, uint8 lineage, uint8 form) external view returns (string memory);
    function vibeName(uint8 vibe) external view returns (string memory);
    function artKey(uint8 stage, uint8 lineage, uint8 form) external view returns (bytes32);
}
