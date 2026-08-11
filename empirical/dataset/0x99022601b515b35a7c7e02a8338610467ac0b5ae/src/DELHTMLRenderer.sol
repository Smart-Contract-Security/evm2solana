// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibString} from "solady/utils/LibString.sol";
import {SSTORE2} from "solady/utils/SSTORE2.sol";
import {DynamicBufferLib} from "solady/utils/DynamicBufferLib.sol";
import {IDELHTMLRenderer, TokenStateView} from "./IDELRenderer.sol";
import {IDELDataStore} from "./DELDataStore.sol";
import {IDELTuner} from "./DELTuner.sol";
import {RenderHelpers} from "./RenderHelpers.sol";

/// @notice Builds the animation_url HTML for a token. Returns raw HTML bytes —
/// the main contract handles base64. Includes the engine bundle by reading the
/// passed-in DataChunk via SSTORE2. Reads the 21 effective parameter values
/// from DELTuner and injects them into window.DEL_CONFIG.
contract DELHTMLRenderer is IDELHTMLRenderer {
    using DynamicBufferLib for DynamicBufferLib.DynamicBuffer;
    using RenderHelpers for *;

    uint256 internal constant PALETTE_BYTES = 76;
    uint256 internal constant MAX_VOIDLING  = 12;

    function html(
        uint256 tokenId,
        TokenStateView calldata v,
        address dataStoreAddr,
        address dataChunk,
        address tunerAddr
    ) external view returns (bytes memory) {
        IDELDataStore dataStore = IDELDataStore(dataStoreAddr);
        DynamicBufferLib.DynamicBuffer memory buf;
        buf.p(dataStore.htmlHead()).p(bytes(LibString.toString(tokenId)));
        buf.p(dataStore.htmlMid()).p(_configLiteral(tokenId, v, dataStore, tunerAddr));
        buf.p(SSTORE2.read(dataChunk));
        return buf.data;
    }

    function _configLiteral(
        uint256 tokenId,
        TokenStateView calldata v,
        IDELDataStore dataStore,
        address tunerAddr
    ) internal view returns (bytes memory) {
        bytes memory palettes = dataStore.palettes();
        bytes memory charSets = dataStore.charSets();
        bytes memory charOffs = dataStore.charSetsOffsets();
        int32[21] memory eff  = IDELTuner(tunerAddr).effectiveFields(tokenId);

        string memory palette = _charSet(charSets, charOffs, v.charSetIdx);

        DynamicBufferLib.DynamicBuffer memory buf;
        // Palette may contain `"` or `\` (e.g. char-set 15 has a literal
        // backslash). JSON-escape before emission so the engine's JSON parse
        // doesn't choke.
        buf.p('{"characterPalette":"').p(_jsonEscapeString(bytes(palette)));
        buf.p('","colorScheme":{"voidling":').p(_voidlingMap(palettes, v.paletteIdx, palette));
        buf.p(',"background":"').p(bytes(_namedColor(palettes, v.paletteIdx, 0)));
        buf.p('","sideColor":"').p(bytes(_namedColor(palettes, v.paletteIdx, 1)));
        buf.p('","topBottomColor":"').p(bytes(_namedColor(palettes, v.paletteIdx, 2)));
        buf.p('","linkColor":"').p(bytes(_namedColor(palettes, v.paletteIdx, 3)));
        buf.p('","textColor":"').p(bytes(_namedColor(palettes, v.paletteIdx, 4)));
        buf.p('","borderColor":"').p(bytes(_namedColor(palettes, v.paletteIdx, 5)));
        buf.p('","plusSignColor":"').p(bytes(_namedColor(palettes, v.paletteIdx, 6)));
        buf.p('"}');

        // 21 numeric fields, keyed exactly as the JS engine expects in
        // window.DEL_CONFIG. Field index → JS key mapping is documented in
        // tools/encode-for-solidity.js BEHAVIOUR_FIELDS.
        buf.p(',"baseRadius":').p(bytes(_fixI32(eff[0])));
        buf.p(',"aspectRatio":').p(bytes(_fixI32(eff[1])));
        buf.p(',"stepSize":').p(bytes(_fixI32(eff[2])));
        buf.p(',"moveSpeed":').p(bytes(_fixI32(eff[3])));
        buf.p(',"maxMoveDistance":').p(bytes(_fixI32(eff[4])));
        buf.p(',"xBias":').p(bytes(_fixI32(eff[5])));
        buf.p(',"yBias":').p(bytes(_fixI32(eff[6])));
        buf.p(',"minRotationSpeed":').p(bytes(_fixI32(eff[7])));
        buf.p(',"maxRotationSpeed":').p(bytes(_fixI32(eff[8])));
        buf.p(',"rotationSmoothness":').p(bytes(_fixI32(eff[9])));
        buf.p(',"maxRotationAngle":').p(bytes(_fixI32(eff[10])));
        buf.p(',"baseDeformStrength":').p(bytes(_fixI32(eff[11])));
        buf.p(',"extraDeformStrength":').p(bytes(_fixI32(eff[12])));
        buf.p(',"deformFrequency":').p(bytes(_fixI32(eff[13])));
        buf.p(',"deformComplexity":').p(bytes(_fixI32(eff[14])));
        buf.p(',"deformSmoothness":').p(bytes(_fixI32(eff[15])));
        buf.p(',"drippiness":').p(bytes(_fixI32(eff[16])));
        buf.p(',"timeSpeed":').p(bytes(_fixI32(eff[17])));
        buf.p(',"perspectiveDistance":').p(bytes(_fixI32(eff[18])));
        buf.p(',"perspectiveStrength":').p(bytes(_fixI32(eff[19])));
        buf.p(',"behaviorChangeTime":').p(bytes(_fixI32(eff[20])));
        buf.p("}");
        return buf.data;
    }

    function _voidlingMap(bytes memory palettes, uint8 paletteIdx, string memory palette)
        internal
        pure
        returns (bytes memory)
    {
        bytes memory pb = bytes(palette);
        DynamicBufferLib.DynamicBuffer memory buf;
        buf.p("{");
        uint256 i;
        uint256 idx;
        bool first = true;
        while (i < pb.length) {
            uint256 cl = RenderHelpers.utf8Len(uint8(pb[i]));
            bytes memory ch = _slice(pb, i, cl);
            if (!first) buf.p(",");
            first = false;
            // Key must be JSON-escaped — palette can contain `"` or `\`.
            buf.p('"').p(_jsonEscapeString(ch)).p('":"').p(bytes(_voidlingHex(palettes, paletteIdx, idx))).p('"');
            i += cl;
            idx += 1;
        }
        buf.p("}");
        return buf.data;
    }

    // JSON-escape the two chars that can break a JSON string literal.
    function _jsonEscapeString(bytes memory s) internal pure returns (bytes memory) {
        DynamicBufferLib.DynamicBuffer memory buf;
        for (uint256 i; i < s.length; i++) {
            bytes1 c = s[i];
            if (c == "\"") {
                buf.p(bytes("\\\""));
            } else if (c == "\\") {
                buf.p(bytes("\\\\"));
            } else {
                bytes memory one = new bytes(1);
                one[0] = c;
                buf.p(one);
            }
        }
        return buf.data;
    }

    // ---------------------------------------------------------------- helpers

    /// @dev Format a scaled int32 (SCALE=10000) as a human-readable number
    /// for JS consumption. Handles negative values for fields like xBias.
    function _fixI32(int32 v) internal pure returns (string memory) {
        if (v < 0) {
            uint32 mag = uint32(-v);
            return string.concat("-", RenderHelpers.fix(uint256(mag)));
        }
        return RenderHelpers.fix(uint256(uint32(v)));
    }

    function _voidlingHex(bytes memory palettes, uint8 paletteIdx, uint256 charIdx) internal pure returns (string memory) {
        uint256 off = uint256(paletteIdx) * PALETTE_BYTES + charIdx * 4;
        return RenderHelpers.toHexColor(bytes4(uint32(RenderHelpers.readU32(palettes, off))));
    }

    function _namedColor(bytes memory palettes, uint8 paletteIdx, uint256 namedIdx) internal pure returns (string memory) {
        uint256 off = uint256(paletteIdx) * PALETTE_BYTES + MAX_VOIDLING * 4 + namedIdx * 4;
        return RenderHelpers.toHexColor(bytes4(uint32(RenderHelpers.readU32(palettes, off))));
    }

    function _charSet(bytes memory charSets, bytes memory charOffs, uint8 idx) internal pure returns (string memory) {
        uint256 off = RenderHelpers.readU16(charOffs, uint256(idx) * 2);
        return RenderHelpers.readLengthPrefixed(charSets, off);
    }

    function _slice(bytes memory src, uint256 offset, uint256 len) internal pure returns (bytes memory out) {
        out = new bytes(len);
        for (uint256 i; i < len; i++) out[i] = src[offset + i];
    }
}
