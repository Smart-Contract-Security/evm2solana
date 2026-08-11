// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

contract DaemonArt {
    string private constant HEAD = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="384" height="384" shape-rendering="crispEdges" style="background:#06070d">';
    string private constant FOOT = '</svg>';

    function paint(
        bytes32 seed,
        bytes32 pulse,
        bool    cleansed,
        bool    halo
    ) public pure returns (string memory) {
        bytes32 visiblePulse = cleansed ? bytes32(0) : pulse;
        bytes memory inner = abi.encodePacked('<rect width="24" height="24" fill="#06070d"/>');

        bytes32 mix = keccak256(abi.encodePacked(seed, visiblePulse, "body"));
        inner = abi.encodePacked(inner, _silhouette(seed, mix));
        inner = abi.encodePacked(inner, _eyes(seed, mix));
        if (!cleansed) {
            inner = abi.encodePacked(inner, _static(seed, visiblePulse));
        }
        if (halo) {
            inner = abi.encodePacked(inner, _halo(seed));
        }
        return string(abi.encodePacked(HEAD, inner, FOOT));
    }

    function _silhouette(bytes32 seed, bytes32 mix) internal pure returns (bytes memory out) {
        string memory bodyColor   = _hue(uint256(mix), 0);
        string memory accentColor = _hue(uint256(seed), 1);
        for (uint256 y = 7; y < 18; y++) {
            for (uint256 xL = 6; xL < 12; xL++) {
                uint256 idx = (y - 7) * 6 + (xL - 6);
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

    function _eyes(bytes32 seed, bytes32 mix) internal pure returns (bytes memory) {
        string memory eyeColor = _irisHue(uint256(seed) ^ uint256(mix));
        uint256 eyeRow = 10 + (uint256(seed) % 3);
        return abi.encodePacked(
            _dot(9, eyeRow, eyeColor),
            _dot(14, eyeRow, eyeColor)
        );
    }

    function _static(bytes32 seed, bytes32 pulse) internal pure returns (bytes memory out) {
        uint256 mix = uint256(keccak256(abi.encodePacked(seed, pulse, "static")));
        uint256 streaks = 1 + (mix % 4);
        for (uint256 i; i < streaks; i++) {
            uint256 r = (mix >> (i * 5)) % 24;
            uint256 a = (mix >> (i * 7 + 3)) % 24;
            uint256 b = (mix >> (i * 11 + 5)) % 24;
            if (a > b) (a, b) = (b, a);
            string memory col = _staticHue((mix >> (i * 13)) & 0xff);
            out = abi.encodePacked(
                out,
                '<rect x="', _itoa(a),
                '" y="', _itoa(r),
                '" width="', _itoa(b - a + 1),
                '" height="1" fill="', col, '" opacity="0.55"/>'
            );
        }
    }

    function _halo(bytes32 seed) internal pure returns (bytes memory) {
        string memory glow = _hue(uint256(seed) ^ 0xa1b2c3, 4);
        return abi.encodePacked(
            '<rect x="0" y="0" width="24" height="24" fill="none" stroke="', glow,
            '" stroke-width="0.6" opacity="0.85"><animate attributeName="opacity" values="0.4;1;0.4" dur="2.4s" repeatCount="indefinite"/></rect>'
        );
    }

    function _dot(uint256 x, uint256 y, string memory color) internal pure returns (bytes memory) {
        return abi.encodePacked(
            '<rect x="', _itoa(x), '" y="', _itoa(y),
            '" width="1" height="1" fill="', color, '"/>'
        );
    }

    function _hue(uint256 hash, uint256 offset) internal pure returns (string memory) {
        uint256 idx = (hash >> (offset * 8)) & 7;
        if (idx == 0) return "#22ccaa";
        if (idx == 1) return "#88ff44";
        if (idx == 2) return "#f7931a";
        if (idx == 3) return "#aa44ff";
        if (idx == 4) return "#88ccff";
        if (idx == 5) return "#ff4488";
        if (idx == 6) return "#ffdd33";
        return "#e5e7f0";
    }

    function _irisHue(uint256 hash) internal pure returns (string memory) {
        uint256 idx = hash & 3;
        if (idx == 0) return "#ffffff";
        if (idx == 1) return "#ffdd33";
        if (idx == 2) return "#ff4488";
        return "#22ccaa";
    }

    function _staticHue(uint256 hash) internal pure returns (string memory) {
        uint256 idx = hash & 3;
        if (idx == 0) return "#ff4488";
        if (idx == 1) return "#22ccaa";
        if (idx == 2) return "#ffdd33";
        return "#aa44ff";
    }

    function glyphURI(
        address holder,
        uint256 slot,
        bytes32 pulse,
        uint64  spawnBlock
    ) external pure returns (string memory) {
        bytes32 seed = keccak256(abi.encodePacked(holder, slot, "DAEMON"));
        string memory svg = paint(seed, pulse, false, false);
        return _pack(
            string(abi.encodePacked("DAEMON Live #", _itoa(slot))),
            "live mutating onchain artifact",
            svg,
            spawnBlock,
            false,
            false
        );
    }

    function frozenURI(
        uint256 tokenId,
        bytes32 seed,
        bytes32 pulse,
        uint64  spawnBlock,
        bool    cleansed,
        bool    halo
    ) external pure returns (string memory) {
        string memory svg = paint(seed, pulse, cleansed, halo);
        return _pack(
            string(abi.encodePacked("DAEMON Husk #", _itoa(tokenId))),
            "sealed DAEMON, mutation state frozen at seal time",
            svg,
            spawnBlock,
            cleansed,
            halo
        );
    }

    function _pack(
        string memory tokenName,
        string memory desc,
        string memory svg,
        uint64  spawnBlock,
        bool    cleansed,
        bool    halo
    ) internal pure returns (string memory) {
        return string(abi.encodePacked(
            'data:application/json;utf8,{"name":"', tokenName,
            '","description":"', desc,
            '","image":"data:image/svg+xml;utf8,', svg,
            '","attributes":[',
              '{"trait_type":"spawn_block","value":', _itoa(uint256(spawnBlock)), '},',
              '{"trait_type":"cleansed","value":"', cleansed ? "true" : "false", '"},',
              '{"trait_type":"halo","value":"', halo ? "true" : "false", '"}',
            ']}'
        ));
    }

    function _itoa(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        uint256 t = v; uint256 d;
        while (t != 0) { d++; t /= 10; }
        bytes memory s = new bytes(d);
        while (v != 0) { d--; s[d] = bytes1(uint8(48 + v % 10)); v /= 10; }
        return string(s);
    }
}
