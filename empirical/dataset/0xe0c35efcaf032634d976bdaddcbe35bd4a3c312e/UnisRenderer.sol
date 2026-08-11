// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/// @title UnisRenderer - shared onchain SVG painter for all Objectized Assets
/// @notice Generates a deterministic 24x24 pixel glyph from
///         (holder, slot, paletteId, poolEntropy). The paletteId picks one
///         of eight built-in palettes; the entropy from the live pool perturbs
///         the body bits, so the glyph mutates as the asset trades.
contract UnisRenderer {
    string private constant HEAD = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="384" height="384" shape-rendering="crispEdges" style="background:#08090c">';
    string private constant FOOT = '</svg>';

    function paint(
        bytes32 seed,
        bytes32 entropy,
        bytes32 paletteId
    ) public pure returns (string memory) {
        bytes memory inner = abi.encodePacked('<rect width="24" height="24" fill="', _bg(paletteId), '"/>');
        bytes32 mix = keccak256(abi.encodePacked(seed, entropy, paletteId, "body"));

        inner = abi.encodePacked(inner, _body(seed, mix, paletteId));
        inner = abi.encodePacked(inner, _eyes(seed, mix, paletteId));
        inner = abi.encodePacked(inner, _frame(paletteId));

        return string(abi.encodePacked(HEAD, inner, FOOT));
    }

    /// @notice Renders the data URI for a particular (holder, slot) on a
    ///         particular asset. `objName` and `objSymbol` are interpolated
    ///         into the metadata JSON.
    function objectURI(
        address holder,
        uint256 slot,
        bytes32 paletteId,
        bytes32 entropy,
        string memory objName,
        string memory objSymbol
    ) external pure returns (string memory) {
        bytes32 seed = keccak256(abi.encodePacked(holder, slot, objSymbol));
        string memory svg = paint(seed, entropy, paletteId);
        return string(abi.encodePacked(
            'data:application/json;utf8,{"name":"',
            objName,
            ' #',
            _itoa(slot),
            unicode'","description":"UNIS Objectized Asset — onchain mutable glyph",',
            '"image":"data:image/svg+xml;utf8,', svg,
            '","attributes":[',
              '{"trait_type":"symbol","value":"', objSymbol, '"},',
              '{"trait_type":"slot","value":', _itoa(slot), '},',
              '{"trait_type":"palette","value":"0x', _hex8(paletteId), '"}',
            ']}'
        ));
    }

    // ---- body ----

    function _body(bytes32 seed, bytes32 mix, bytes32 paletteId) internal pure returns (bytes memory out) {
        string memory bodyColor   = _hue(paletteId, uint256(mix), 0);
        string memory accentColor = _hue(paletteId, uint256(seed), 1);
        for (uint256 y = 6; y < 19; y++) {
            for (uint256 xL = 6; xL < 12; xL++) {
                uint256 idx = (y - 6) * 6 + (xL - 6);
                uint256 bit = (uint256(mix) >> (idx % 256)) & 1;
                if (bit == 1) {
                    uint256 xR = 23 - xL;
                    bool accent = ((uint256(seed) >> (idx % 256)) & 1) == 1;
                    string memory color = accent ? accentColor : bodyColor;
                    out = abi.encodePacked(out, _dot(xL, y, color));
                    if (xR != xL) {
                        out = abi.encodePacked(out, _dot(xR, y, color));
                    }
                }
            }
        }
    }

    function _eyes(bytes32 seed, bytes32 mix, bytes32 paletteId) internal pure returns (bytes memory) {
        string memory eyeColor = _hue(paletteId, uint256(seed) ^ uint256(mix), 4);
        uint256 eyeRow = 9 + (uint256(seed) % 3);
        return abi.encodePacked(
            _dot(9, eyeRow, eyeColor),
            _dot(14, eyeRow, eyeColor)
        );
    }

    function _frame(bytes32 paletteId) internal pure returns (bytes memory) {
        string memory frameColor = _hue(paletteId, uint256(paletteId), 7);
        return abi.encodePacked(
            '<rect x="0" y="0" width="24" height="24" fill="none" stroke="',
            frameColor,
            '" stroke-width="0.4" opacity="0.55"/>'
        );
    }

    function _dot(uint256 x, uint256 y, string memory color) internal pure returns (bytes memory) {
        return abi.encodePacked(
            '<rect x="', _itoa(x), '" y="', _itoa(y),
            '" width="1" height="1" fill="', color, '"/>'
        );
    }

    // ---- palette ----

    /// @dev The low 3 bytes of paletteId pick a palette family;
    ///      `idxOffset` rotates the colour within the family.
    function _hue(bytes32 paletteId, uint256 hash, uint256 idxOffset) internal pure returns (string memory) {
        uint8 family = uint8(uint256(paletteId) & 0x07);
        uint256 idx = (hash >> (idxOffset * 8)) & 7;
        // 8 palettes x 8 colours; only the first colour of each is constant,
        // the rest follow the same pattern as the family seed.
        if (family == 0) return _violet(idx);
        if (family == 1) return _ember(idx);
        if (family == 2) return _kelp(idx);
        if (family == 3) return _bronze(idx);
        if (family == 4) return _ice(idx);
        if (family == 5) return _bubble(idx);
        if (family == 6) return _gold(idx);
        return _ash(idx);
    }

    function _bg(bytes32 paletteId) internal pure returns (string memory) {
        uint8 family = uint8(uint256(paletteId) & 0x07);
        if (family == 0) return "#0e0918";
        if (family == 1) return "#180a0a";
        if (family == 2) return "#08120f";
        if (family == 3) return "#1a1208";
        if (family == 4) return "#0a1218";
        if (family == 5) return "#180e16";
        if (family == 6) return "#181208";
        return "#0c0c10";
    }

    function _violet(uint256 i) internal pure returns (string memory) {
        if (i == 0) return "#c084fc";
        if (i == 1) return "#a855f7";
        if (i == 2) return "#7c3aed";
        if (i == 3) return "#f0abfc";
        if (i == 4) return "#ffffff";
        if (i == 5) return "#d8b4fe";
        if (i == 6) return "#581c87";
        return "#e9d5ff";
    }
    function _ember(uint256 i) internal pure returns (string memory) {
        if (i == 0) return "#fb923c";
        if (i == 1) return "#f97316";
        if (i == 2) return "#ea580c";
        if (i == 3) return "#fde68a";
        if (i == 4) return "#fef3c7";
        if (i == 5) return "#dc2626";
        if (i == 6) return "#7f1d1d";
        return "#fef9c3";
    }
    function _kelp(uint256 i) internal pure returns (string memory) {
        if (i == 0) return "#22c55e";
        if (i == 1) return "#16a34a";
        if (i == 2) return "#15803d";
        if (i == 3) return "#a7f3d0";
        if (i == 4) return "#d1fae5";
        if (i == 5) return "#14b8a6";
        if (i == 6) return "#064e3b";
        return "#bbf7d0";
    }
    function _bronze(uint256 i) internal pure returns (string memory) {
        if (i == 0) return "#b5883a";
        if (i == 1) return "#d4ad55";
        if (i == 2) return "#9c6e2a";
        if (i == 3) return "#e6c97a";
        if (i == 4) return "#f3e3b1";
        if (i == 5) return "#7a5a22";
        if (i == 6) return "#46341a";
        return "#cea968";
    }
    function _ice(uint256 i) internal pure returns (string memory) {
        if (i == 0) return "#38bdf8";
        if (i == 1) return "#0ea5e9";
        if (i == 2) return "#0284c7";
        if (i == 3) return "#bae6fd";
        if (i == 4) return "#e0f2fe";
        if (i == 5) return "#7dd3fc";
        if (i == 6) return "#075985";
        return "#c4e5fa";
    }
    function _bubble(uint256 i) internal pure returns (string memory) {
        if (i == 0) return "#ec4899";
        if (i == 1) return "#f472b6";
        if (i == 2) return "#db2777";
        if (i == 3) return "#fce7f3";
        if (i == 4) return "#fbcfe8";
        if (i == 5) return "#9d174d";
        if (i == 6) return "#831843";
        return "#f9a8d4";
    }
    function _gold(uint256 i) internal pure returns (string memory) {
        if (i == 0) return "#facc15";
        if (i == 1) return "#eab308";
        if (i == 2) return "#ca8a04";
        if (i == 3) return "#fef08a";
        if (i == 4) return "#fef9c3";
        if (i == 5) return "#a16207";
        if (i == 6) return "#713f12";
        return "#fde047";
    }
    function _ash(uint256 i) internal pure returns (string memory) {
        if (i == 0) return "#94a3b8";
        if (i == 1) return "#cbd5e1";
        if (i == 2) return "#475569";
        if (i == 3) return "#e2e8f0";
        if (i == 4) return "#f1f5f9";
        if (i == 5) return "#334155";
        if (i == 6) return "#1e293b";
        return "#64748b";
    }

    // ---- utils ----

    function _itoa(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        uint256 t = v; uint256 d;
        while (t != 0) { d++; t /= 10; }
        bytes memory s = new bytes(d);
        while (v != 0) { d--; s[d] = bytes1(uint8(48 + v % 10)); v /= 10; }
        return string(s);
    }

    function _hex8(bytes32 b) internal pure returns (string memory) {
        bytes memory hexChars = "0123456789abcdef";
        bytes memory s = new bytes(8);
        for (uint256 i; i < 4; i++) {
            s[i*2]   = hexChars[uint8(b[i] >> 4)];
            s[i*2+1] = hexChars[uint8(b[i] & 0x0f)];
        }
        return string(s);
    }
}
