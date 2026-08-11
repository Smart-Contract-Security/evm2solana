// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library Base64 {
    bytes internal constant TABLE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    function encode(bytes memory data) internal pure returns (string memory) {
        if (data.length == 0) return "";
        bytes memory table = TABLE;
        uint256 encodedLen = 4 * ((data.length + 2) / 3);
        bytes memory result = new bytes(encodedLen + 32);
        assembly {
            let tablePtr := add(table, 1)
            let resultPtr := add(result, 32)
            for { let i := 0 } lt(i, mload(data)) { } {
                i := add(i, 3)
                let input := and(mload(add(data, i)), 0xffffff)
                let out := mload(add(tablePtr, and(shr(18, input), 0x3F)))
                out := shl(8, out)
                out := add(out, and(mload(add(tablePtr, and(shr(12, input), 0x3F))), 255))
                out := shl(8, out)
                out := add(out, and(mload(add(tablePtr, and(shr(6, input), 0x3F))), 255))
                out := shl(8, out)
                out := add(out, and(mload(add(tablePtr, and(input, 0x3F))), 255))
                out := shl(224, out)
                mstore(resultPtr, out)
                resultPtr := add(resultPtr, 4)
            }
            switch mod(mload(data), 3)
            case 1 { mstore(sub(resultPtr, 2), shl(240, 0x3d3d)) }
            case 2 { mstore(sub(resultPtr, 1), shl(248, 0x3d)) }
            mstore(result, encodedLen)
        }
        return string(result);
    }
}

library Str {
    function i(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        uint256 tmp = v;
        uint256 len;
        while (tmp != 0) { len++; tmp /= 10; }
        bytes memory buf = new bytes(len);
        while (v != 0) { buf[--len] = bytes1(uint8(48 + v % 10)); v /= 10; }
        return string(buf);
    }

    function h(uint256 v) internal pure returns (string memory) {
        bytes memory hex_ = "0123456789abcdef";
        bytes memory buf = new bytes(6);
        buf[0] = hex_[(v >> 20) & 0xF];
        buf[1] = hex_[(v >> 16) & 0xF];
        buf[2] = hex_[(v >> 12) & 0xF];
        buf[3] = hex_[(v >>  8) & 0xF];
        buf[4] = hex_[(v >>  4) & 0xF];
        buf[5] = hex_[(v      ) & 0xF];
        return string(buf);
    }
}

contract FragmentXRenderer {

    struct Params {
        uint256 fragCount;
        uint256 glitchCount;
        uint256 baseHue;
        uint256 palIdx;
        bool    scanlines;
    }

    function tokenURI(uint256 tokenId, uint8 tier, bytes32 seed)
        external pure returns (string memory)
    {
        Params memory p = _params(seed, tier);
        string memory svg = _svg(p, tier);
        string memory json = string(abi.encodePacked(
            '{"name":"FragmentX #', Str.i(tokenId),
            '","description":"Fully on-chain soyut geometrik glitch sanat.","image":"data:image/svg+xml;base64,',
            Base64.encode(bytes(svg)),
            '","attributes":[',
            '{"trait_type":"Tier","value":"',       _tierName(tier), '"},',
            '{"trait_type":"Fragments","value":', Str.i(p.fragCount),  '},',
            '{"trait_type":"Glitch","value":',    Str.i(p.glitchCount),'},',
            '{"trait_type":"Palette","value":"',  _palName(p.palIdx),  '"}',
            ']}'
        ));
        return string(abi.encodePacked(
            "data:application/json;base64,", Base64.encode(bytes(json))
        ));
    }

    function _params(bytes32 seed, uint8 tier) internal pure returns (Params memory p) {
        uint256 s = uint256(seed);
        p.baseHue    = s % 360;             s >>= 9;
        p.palIdx     = s % 5;               s >>= 3;
        if (tier == 0) {
            p.fragCount   = 6  + (s % 5);  s >>= 3;
            p.glitchCount = 1  + (s % 2);
            p.scanlines   = false;
        } else if (tier == 1) {
            p.fragCount   = 10 + (s % 7);  s >>= 3;
            p.glitchCount = 3  + (s % 3);
            p.scanlines   = false;
        } else {
            p.fragCount   = 16 + (s % 9);  s >>= 4;
            p.glitchCount = 6  + (s % 4);
            p.scanlines   = true;
        }
    }

    function _svg(Params memory p, uint8 tier) internal pure returns (string memory) {
        string memory bg = tier == 0 ? "#0f172a" : tier == 1 ? "#0d0d2b" : "#100500";
        string memory body = string(abi.encodePacked(
            _fragments(p),
            _glitchBars(p, tier),
            p.scanlines ? _scanlines(p) : ""
        ));
        return string(abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 300 300">',
            '<rect width="300" height="300" fill="', bg, '"/>',
            body,
            '</svg>'
        ));
    }

    function _hsl(uint256 h, uint256 s, uint256 l) internal pure returns (string memory) {
        return string(abi.encodePacked(
            "hsl(", Str.i(h % 360), ",", Str.i(s), "%,", Str.i(l), "%)"
        ));
    }

    function _fragColor(uint256 idx, uint256 baseHue, uint256 palIdx, uint256 total, bytes32 seed)
        internal pure returns (string memory)
    {
        uint256 s = uint256(keccak256(abi.encode(seed, idx)));
        uint256 h;
        uint256 sat;
        uint256 lit;
        if (palIdx == 0) { h = baseHue; sat = 20 + s % 30; lit = 40 + s % 30; }
        else if (palIdx == 1) { h = idx % 2 == 0 ? baseHue : (baseHue + 180) % 360; sat = 60; lit = 40 + s % 20; }
        else if (palIdx == 2) { h = (baseHue + idx * 120) % 360; sat = 70; lit = 40 + s % 20; }
        else if (palIdx == 3) { h = (baseHue + idx * (360 / (total == 0 ? 1 : total))) % 360; sat = 90; lit = 55 + s % 20; }
        else { h = baseHue; sat = 5 + s % 15; lit = 30 + s % 40; }
        return _hsl(h, sat, lit);
    }

    function _polygon(uint256 cx, uint256 cy, uint256 size, uint256 sides, uint256 rotSeed)
        internal pure returns (string memory)
    {
        string memory pts = "";
        for (uint256 v = 0; v < sides; v++) {
            uint256 rSeed = uint256(keccak256(abi.encode(rotSeed, v)));
            uint256 r = size * (70 + rSeed % 60) / 100;
            uint256 angleNum = v * 628318 / sides + (rotSeed % 628318);
            int256 px = int256(cx) + int256(r) * _cos(angleNum) / 1000;
            int256 py = int256(cy) + int256(r) * _sin(angleNum) / 1000;
            pts = string(abi.encodePacked(pts, v == 0 ? "" : " ", _istr(px), ",", _istr(py)));
        }
        return pts;
    }

    function _fragments(Params memory p) internal pure returns (string memory) {
        string memory out = "";
        bytes32 fseed = keccak256(abi.encode(p.baseHue, p.palIdx, p.fragCount));
        for (uint256 i = 0; i < p.fragCount; i++) {
            uint256 s = uint256(keccak256(abi.encode(fseed, i)));
            uint256 cx   = 10 + s % 280;           s >>= 8;
            uint256 cy   = 10 + s % 280;           s >>= 8;
            uint256 size = 20 + s % 80;            s >>= 7;
            uint256 sides= 3  + s % 5;             s >>= 3;
            uint256 opac = 30 + s % 60;
            string memory col = _fragColor(i, p.baseHue, p.palIdx, p.fragCount, fseed);
            string memory pts = _polygon(cx, cy, size, sides, s);
            out = string(abi.encodePacked(out,
                '<polygon points="', pts, '" fill="', col,
                '" stroke="', col, '" stroke-width="0.8" opacity="0.', Str.i(opac), '"/>'
            ));
        }
        return out;
    }

    function _glitchBars(Params memory p, uint8 tier) internal pure returns (string memory) {
        string memory out = "";
        bytes32 gseed = keccak256(abi.encode(p.baseHue, "glitch", p.glitchCount));
        for (uint256 g = 0; g < p.glitchCount; g++) {
            uint256 s  = uint256(keccak256(abi.encode(gseed, g)));
            uint256 gy = s % 290;                  s >>= 8;
            uint256 gh = 2 + s % 8;               s >>= 4;
            uint256 gw = 60 + s % 200;            s >>= 8;
            uint256 gx = s % (300 - gw);          s >>= 8;
            int256  shift = int256(s % 20) - 10;  s >>= 5;
            uint256 h2 = (p.baseHue + 180) % 360;
            uint256 alpha = tier == 0 ? 40 : tier == 1 ? 60 : 80;
            string memory shiftX = _istr(int256(gx) + shift);
            out = string(abi.encodePacked(out,
                '<rect x="', shiftX, '" y="', Str.i(gy),
                '" width="', Str.i(gw), '" height="', Str.i(gh),
                '" fill="', _hsl(h2, 80, 60), '" opacity="0.', Str.i(alpha), '"/>'
            ));
        }
        return out;
    }

    function _scanlines(Params memory p) internal pure returns (string memory) {
        string memory out = "";
        bytes32 sseed = keccak256(abi.encode(p.baseHue, "scan"));
        for (uint256 sc = 0; sc < 8; sc++) {
            uint256 s  = uint256(keccak256(abi.encode(sseed, sc)));
            uint256 sx = s % 240;            s >>= 8;
            uint256 sy = s % 290;            s >>= 8;
            uint256 sl = 10 + s % 60;
            uint256 hc = (p.baseHue + sc * 45) % 360;
            out = string(abi.encodePacked(out,
                '<line x1="', Str.i(sx), '" y1="', Str.i(sy),
                '" x2="', Str.i(sx + sl), '" y2="', Str.i(sy),
                '" stroke="', _hsl(hc, 90, 70), '" stroke-width="0.5" opacity="0.6"/>'
            ));
        }
        return out;
    }

    function _cos(uint256 angleMillirad) internal pure returns (int256) {
        uint256 a = angleMillirad % 628318;
        if (a > 314159) a = 628318 - a;
        int256 x = int256(a);
        int256 c = 1000 - (x * x) / 197392 + (x * x / 14142) * (x * x / 14142) / 197392;
        if (angleMillirad % 628318 > 157079 && angleMillirad % 628318 < 471238) c = -c;
        return c;
    }

    function _sin(uint256 angleMillirad) internal pure returns (int256) {
        return _cos(angleMillirad + 471238);
    }

    function _istr(int256 v) internal pure returns (string memory) {
        if (v < 0) return string(abi.encodePacked("-", Str.i(uint256(-v))));
        return Str.i(uint256(v));
    }

    function _tierName(uint8 tier) internal pure returns (string memory) {
        if (tier == 0) return "Common";
        if (tier == 1) return "Rare";
        return "Legendary";
    }

    function _palName(uint256 idx) internal pure returns (string memory) {
        if (idx == 0) return "Mono";
        if (idx == 1) return "Dual";
        if (idx == 2) return "Triad";
        if (idx == 3) return "Neon";
        return "Ash";
    }
}
