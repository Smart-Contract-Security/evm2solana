// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IOCCV2SVGRenderer — Interface for the SVG composition engine
/// @notice OCC V2's renderer takes the background color as an explicit
///         parameter (drawn inline as a solid `<rect>`) rather than reading
///         a Background SVG variant from the trait registry. The Background
///         slot in the registry is vestigial on V2.
interface IOCCV2SVGRenderer {
    function renderSVG(
        uint16[14] calldata traitIndices,
        bool isMale,
        bytes3 backgroundColor,
        bytes3 skinColor,
        bytes3 hairColor,
        bytes3 clothingColor
    ) external view returns (string memory);
}
