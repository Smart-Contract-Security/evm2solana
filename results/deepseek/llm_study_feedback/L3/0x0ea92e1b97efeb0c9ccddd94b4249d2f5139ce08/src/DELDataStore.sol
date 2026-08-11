// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract DELData {
    bytes public constant BEHAVIOUR_DEFAULTS = hex"0000000000000000000000000000000000000000000000000000000000000000";
    bytes public constant CHAR_SETS = hex"0000000000000000000000000000000000000000000000000000000000000000";
    bytes public constant CHAR_SETS_OFFSETS = hex"0000000000000000000000000000000000000000000000000000000000000000";
    bytes public constant PALETTES = hex"0000000000000000000000000000000000000000000000000000000000000000";
    bytes public constant PALETTE_NAMES = hex"0000000000000000000000000000000000000000000000000000000000000000";
    bytes public constant PALETTE_NAMES_OFFSETS = hex"0000000000000000000000000000000000000000000000000000000000000000";
    bytes public constant TUPLES = hex"0000000000000000000000000000000000000000000000000000000000000000";
    bytes public constant HTML_HEAD = hex"0000000000000000000000000000000000000000000000000000000000000000";
    bytes public constant HTML_MID = hex"0000000000000000000000000000000000000000000000000000000000000000";
}

contract DELDataStore {
    function behaviourDefaults() external pure returns (bytes memory) { return DELData.BEHAVIOUR_DEFAULTS; }
    function charSets() external pure returns (bytes memory) { return DELData.CHAR_SETS; }
    function charSetsOffsets() external pure returns (bytes memory) { return DELData.CHAR_SETS_OFFSETS; }
    function palettes() external pure returns (bytes memory) { return DELData.PALETTES; }
    function paletteNames() external pure returns (bytes memory) { return DELData.PALETTE_NAMES; }
    function paletteNamesOffsets() external pure returns (bytes memory) { return DELData.PALETTE_NAMES_OFFSETS; }
    function tuples() external pure returns (bytes memory) { return DELData.TUPLES; }
    function htmlHead() external pure returns (bytes memory) { return DELData.HTML_HEAD; }
    function htmlMid() external pure returns (bytes memory) { return DELData.HTML_MID; }
}

interface IDELDataStore {
    function behaviourDefaults() external view returns (bytes memory);
    function charSets() external view returns (bytes memory);
    function charSetsOffsets() external view returns (bytes memory);
    function palettes() external view returns (bytes memory);
    function paletteNames() external view returns (bytes memory);
    function paletteNamesOffsets() external view returns (bytes memory);
    function tuples() external view returns (bytes memory);
    function htmlHead() external view returns (bytes memory);
    function htmlMid() external view returns (bytes memory);
}