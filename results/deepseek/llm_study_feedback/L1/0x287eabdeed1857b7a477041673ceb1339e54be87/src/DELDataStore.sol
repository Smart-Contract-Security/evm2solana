// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DELData} from "./DELData.sol";

/// @notice Holds the immutable config tables as on-chain bytecode constants.
/// Deployed separately so its bytecode doesn't bloat the renderer. Renderers
/// and the tuner call the view functions here to read each table; the calls
/// are cheap STATICCALLs.
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