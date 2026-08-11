pragma solidity 0.8.34;

contract Renderer {
    string private constant HEAD = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="384" height="384" shape-rendering="crispEdges" style="background:#06070d">';
    string private constant FOOT = '</svg>';

    function render(
        bytes32 seed,
        bytes32 corruption,
        bool    sanitized,
        bool    aura
    ) public pure returns (string memory) {
        bytes32 visualCorruption = sanitized ? bytes32(0) : corruption;
        bytes memory inner = abi.encodePacked('<rect width="24" height="24" fill="#06070d"/>');

        bytes32 mix = keccak256(abi.encodePacked(seed, visualCorruption, "body"));
        inner = abi.encodePacked(inner, _body(seed, mix));
        inner = abi.encodePacked(inner, _eyes(seed, mix));
        if (!sanitized) {
            inner = abi.encodePacked(inner, _glitch(seed, visualCorruption));
        }
        if (aura) {
            inner = abi.encodePacked(inner, _aura(seed));
        }
        return string(abi.encodePacked(HEAD, inner, FOOT));
    }

    function _body(bytes32 seed, bytes32 mix) internal pure returns (bytes memory out) {
        string memory bodyColor   = _color(uint256(mix), 0);
        string memory accentColor = _color(uint256(seed), 1);
        for (uint256 y = 7; y < 18; y++) {
            for (uint256 xL = 6; xL < 12; xL++) {
                uint256 idx = (y - 7) * 6 + (xL - 6);
                uint256 bit = (uint256(mix) >> (idx % 256)) & 1;
                if (bit == 1) {
                    uint256 xR = 23 - xL;
                    bool accent = ((uint256(seed) >> (idx % 256)) & 1) == 1;
                    string memory color = accent ? accentColor : bodyColor;
                    out = abi.encodePacked(out, _pixel(xL, y, color));
                    if (xR != xL) {
                        out = abi.encodePacked(out, _pixel(xR, y, color));
                    }
                }
            }
        }
    }

    function _eyes(bytes32 seed, bytes32 mix) internal pure returns (bytes memory) {
        string memory eyeColor = _eyeColor(uint256(seed) ^ uint256(mix));
        uint256 eyeRow = 10 + (uint256(seed) % 3);
        return abi.encodePacked(
            _pixel(9, eyeRow, eyeColor),
            _pixel(14, eyeRow, eyeColor)
        );
    }

    function _glitch(bytes32 seed, bytes32 corruption) internal pure returns (bytes memory out) {
        uint256 mix = uint256(keccak256(abi.encodePacked(seed, corruption, "glitch")));
        uint256 streaks = 1 + (mix % 4);
        for (uint256 i; i < streaks; i++) {
            uint256 r = (mix >> (i * 5)) % 24;
            uint256 a = (mix >> (i * 7 + 3)) % 24;
            uint256 b = (mix >> (i * 11 + 5)) % 24;
            if (a > b) (a, b) = (b, a);
            string memory col = _glitchColor((mix >> (i * 13)) & 0xff);
            out = abi.encodePacked(
                out,
                '<rect x="', _itoa(a),
                '" y="', _itoa(r),
                '" width="', _itoa(b - a + 1),
                '" height="1" fill="', col, '" opacity="0.55"/>'
            );
        }
    }

    function _aura(bytes32 seed) internal pure returns (bytes memory) {
        string memory glow = _color(uint256(seed) ^ 0xa1b2c3, 4);
        return abi.encodePacked(
            '<rect x="0" y="0" width="24" height="24" fill="none" stroke="', glow,
            '" stroke-width="0.6" opacity="0.85"><animate attributeName="opacity" values="0.4;1;0.4" dur="2.4s" repeatCount="indefinite"/></rect>'
        );
    }

    function _pixel(uint256 x, uint256 y, string memory color) internal pure returns (bytes memory) {
        return abi.encodePacked(
            '<rect x="', _itoa(x), '" y="', _itoa(y),
            '" width="1" height="1" fill="', color, '"/>'
        );
    }

    function _color(uint256 hash, uint256 offset) internal pure returns (string memory) {
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

    function _eyeColor(uint256 hash) internal pure returns (string memory) {
        uint256 idx = hash & 3;
        if (idx == 0) return "#ffffff";
        if (idx == 1) return "#ffdd33";
        if (idx == 2) return "#ff4488";
        return "#22ccaa";
    }

    function _glitchColor(uint256 hash) internal pure returns (string memory) {
        uint256 idx = hash & 3;
        if (idx == 0) return "#ff4488";
        if (idx == 1) return "#22ccaa";
        if (idx == 2) return "#ffdd33";
        return "#aa44ff";
    }

    function objectURI(
        address holder,
        uint256 slot,
        bytes32 corruption,
        uint64  spawnBlock
    ) external pure returns (string memory) {
        bytes32 seed = keccak256(abi.encodePacked(holder, slot, "DAEMON"));
        string memory svg = render(seed, corruption, false, false);
        return _wrap(
            string(abi.encodePacked("DAEMON Live #", _itoa(slot))),
            "live mutating onchain artifact",
            svg,
            spawnBlock,
            false,
            false
        );
    }

    function tokenURI(
        uint256 tokenId,
        bytes32 seed,
        bytes32 corruption,
        uint64  spawnBlock,
        bool    sanitized,
        bool    aura
    ) external pure returns (string memory) {
        string memory svg = render(seed, corruption, sanitized, aura);
        return _wrap(
            string(abi.encodePacked("Frozen DAEMON #", _itoa(tokenId))),
            "wrapped DAEMON, mutation state frozen at wrap time",
            svg,
            spawnBlock,
            sanitized,
            aura
        );
    }

    function _wrap(
        string memory name,
        string memory desc,
        string memory svg,
        uint64  spawnBlock,
        bool    sanitized,
        bool    aura
    ) internal pure returns (string memory) {
        return string(abi.encodePacked(
            'data:application/json;utf8,{"name":"', name,
            '","description":"', desc,
            '","image":"data:image/svg+xml;utf8,', svg,
            '","attributes":[',
              '{"trait_type":"spawn_block","value":', _itoa(uint256(spawnBlock)), '},',
              '{"trait_type":"sanitized","value":"', sanitized ? "true" : "false", '"},',
              '{"trait_type":"aura","value":"', aura ? "true" : "false", '"}',
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
