// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @dev Shared per-token state struct passed from DEL to the renderers.
/// Just the per-token identity flags — the renderers fetch the 21
/// effective numeric parameters from the tuner contract directly.
struct TokenStateView {
    address owner;
    uint8 charSetIdx;
    uint8 paletteIdx;
    uint8 behaviourIdx;
    bool  tuned;
}

/// @dev SVG renderer interface. The tuner address lets the renderer resolve
/// the per-token effective parameter values (override-if-set else default).
interface IDELSVGRenderer {
    function svg(uint256 tokenId, TokenStateView calldata v, address dataStore, address tuner)
        external
        view
        returns (bytes memory);
}

/// @dev HTML renderer interface — same shape, plus dataChunk for the engine
/// bundle.
interface IDELHTMLRenderer {
    function html(uint256 tokenId, TokenStateView calldata v, address dataStore, address dataChunk, address tuner)
        external
        view
        returns (bytes memory);
}