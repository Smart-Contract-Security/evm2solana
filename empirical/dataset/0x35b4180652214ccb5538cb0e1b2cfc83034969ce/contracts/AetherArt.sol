// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {LibString} from "./solady/utils/LibString.sol";
import {Base64} from "./solady/utils/Base64.sol";

/// @title AetherArt
/// @notice On-chain pixel angel SVG for AETHERIALS mirror NFTs (24×24 grid).
library AetherArt {
    using LibString for uint256;

    function svg(bytes32 seed, uint256 tokenId) internal pure returns (string memory) {
        uint256 h = uint256(seed);
        uint256 mixed = uint256(keccak256(abi.encode(seed, tokenId)));

        string memory bg = _bgColor(_pick(mixed, 0, 6));
        string memory halo = _haloColor(h);
        string memory body = _bodyColor(_pick(mixed, 5, 5));
        string memory eye = _eyeColor(_pick(mixed, 7, 4));
        string memory wings = _wingColor(halo, _pick(mixed, 4, 4));
        uint256 haloStyle = _pick(mixed, 1, 6);
        uint256 eyeStyle = _pick(mixed, 2, 7);
        uint256 wingStyle = _pick(mixed, 3, 5);
        uint256 acc = _pick(mixed, 6, 4);
        bool aura = _pick(mixed, 14, 3) != 0;
        uint256 headShift = _pick(mixed, 15, 3);
        if (headShift >= 1) headShift -= 1;
        uint256 hx = 9 + headShift;

        return string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="480" height="480" shape-rendering="crispEdges">',
            '<rect width="24" height="24" fill="',
            bg,
            '"/>',
            _particles(halo, eye, mixed, aura),
            _renderHalo(haloStyle, halo, mixed),
            _rect(hx, 4, 6, 5, body, "1"),
            _rect(hx - 1, 5, 1, 3, body, "1"),
            _rect(hx + 6, 5, 1, 3, body, "1"),
            _renderEyes(eyeStyle, eye, body, mixed),
            _rect(hx, 9, 6, 6, body, "0.9"),
            _rect(hx - 1, 10, 1, 4, body, "0.7"),
            _rect(hx + 6, 10, 1, 4, body, "0.7"),
            _robeStripe(body, halo, mixed),
            _wingsLeft(wingStyle, wings, mixed),
            _wingsRight(wingStyle, wings, mixed),
            _accessory(acc, halo, mixed),
            _rect(8, 15, 8, 5, body, "0.8"),
            _rect(7, 16, 1, 3, body, "0.5"),
            _rect(16, 16, 1, 3, body, "0.5"),
            _rect(9, 20, 2, 1, body, "0.6"),
            _rect(13, 20, 2, 1, body, "0.6"),
            '<text x="12" y="23" text-anchor="middle" font-family="monospace" font-size="1.2" fill="',
            halo,
            '">#',
            tokenId.toString(),
            "</text></svg>"
        );
    }

    function tokenURI(bytes32 seed, uint256 tokenId) internal pure returns (string memory) {
        uint256 mixed = uint256(keccak256(abi.encode(seed, tokenId)));
        string memory image = svg(seed, tokenId);
        string[6] memory ranks = ["SERAPHIM", "CHERUBIM", "OPHANIM", "THRONE", "VIRTUE", "POWER"];
        string[6] memory halos = ["Crown", "Ring", "Cross", "Beam", "Wide", "Fractured"];
        string[7] memory eyes = ["Glow", "X", "Sleepy", "Bars", "Star", "Dash", "Wink"];
        string[5] memory wingNames = ["Layered", "Short", "Seraph", "Asymmetric", "Shadow"];
        string memory aura = _pick(mixed, 14, 3) != 0 ? "ON" : "OFF";

        string memory json = string.concat(
            '{"name":"Aetherial #',
            tokenId.toString(),
            '","description":"AETHERIALS on-chain pixel angel.","image":"data:image/svg+xml;base64,',
            Base64.encode(bytes(image)),
            '","attributes":[{"trait_type":"Rank","value":"',
            ranks[_pick(mixed, 13, 6)],
            '"},{"trait_type":"Halo","value":"',
            halos[_pick(mixed, 1, 6)],
            '"},{"trait_type":"Eyes","value":"',
            eyes[_pick(mixed, 2, 7)],
            '"},{"trait_type":"Wings","value":"',
            wingNames[_pick(mixed, 3, 5)],
            '"},{"trait_type":"Aura","value":"',
            aura,
            '"}]}'
        );
        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    function _pick(uint256 mixed, uint256 shift, uint256 mod) private pure returns (uint256) {
        return (mixed >> (shift * 8)) % mod;
    }

    function _rect(uint256 x, uint256 y, uint256 w, uint256 h, string memory fill, string memory op)
        private
        pure
        returns (string memory)
    {
        return string.concat(
            '<rect x="',
            x.toString(),
            '" y="',
            y.toString(),
            '" width="',
            w.toString(),
            '" height="',
            h.toString(),
            '" fill="',
            fill,
            '" opacity="',
            op,
            '"/>'
        );
    }

    function _bgColor(uint256 i) private pure returns (string memory) {
        if (i == 0) return "#071410";
        if (i == 1) return "#040d0b";
        if (i == 2) return "#0a1020";
        if (i == 3) return "#100818";
        if (i == 4) return "#001810";
        return "#120808";
    }

    function _haloColor(uint256 h) private pure returns (string memory) {
        uint256[8] memory palette = [uint256(0), 1, 2, 3, 4, 5, 6, 7];
        uint256 i = palette[h % 8];
        if (i == 0) return "#ffd700";
        if (i == 1) return "#00ffcc";
        if (i == 2) return "#ffffff";
        if (i == 3) return "#ff9900";
        if (i == 4) return "#cc88ff";
        if (i == 5) return "#ff6688";
        if (i == 6) return "#88ffaa";
        return "#aabbcc";
    }

    function _bodyColor(uint256 i) private pure returns (string memory) {
        if (i == 0) return "#c8f0e8";
        if (i == 1) return "#b8e0d8";
        if (i == 2) return "#d8fff0";
        if (i == 3) return "#e0d8c8";
        return "#c0e8ff";
    }

    function _eyeColor(uint256 i) private pure returns (string memory) {
        if (i == 0) return "#00ffcc";
        if (i == 1) return "#ffd700";
        if (i == 2) return "#ffffff";
        return "#ff6688";
    }

    function _wingColor(string memory halo, uint256 i) private pure returns (string memory) {
        if (i == 0) return halo;
        if (i == 1) return "#446655";
        if (i == 2) return "#6688aa";
        return "#554433";
    }

    function _renderHalo(uint256 style, string memory color, uint256 mixed) private pure returns (string memory) {
        mixed;
        if (style == 1) {
            return string.concat(
                _rect(7, 0, 10, 1, color, "0.5"),
                _rect(6, 1, 12, 1, color, "0.35"),
                _rect(5, 2, 14, 1, color, "0.2")
            );
        }
        if (style == 2) {
            return string.concat(_rect(11, 0, 2, 4, color, "0.8"), _rect(8, 2, 8, 1, color, "0.8"));
        }
        if (style == 3) return _rect(9, 1, 6, 1, color, "1");
        if (style == 4) {
            return string.concat(_rect(5, 1, 14, 1, color, "0.9"), _rect(7, 0, 10, 1, color, "0.5"));
        }
        if (style == 5) {
            return string.concat(
                _rect(7, 1, 4, 1, color, "0.9"),
                _rect(13, 1, 4, 1, color, "0.9"),
                _rect(10, 2, 4, 1, color, "0.4")
            );
        }
        return string.concat(_rect(8, 1, 8, 1, color, "1"), _rect(6, 2, 12, 1, color, "0.7"));
    }

    function _renderEyes(uint256 style, string memory eye, string memory body, uint256 mixed)
        private
        pure
        returns (string memory)
    {
        uint256 y = 6 + _pick(mixed, 8, 2);
        if (style == 1) {
            return string.concat(
                _rect(9, y, 1, 1, eye, "1"),
                _rect(10, y + 1, 1, 1, eye, "1"),
                _rect(14, y, 1, 1, eye, "1"),
                _rect(13, y + 1, 1, 1, eye, "1")
            );
        }
        if (style == 2) return _rect(9, y, 5, 1, eye, "0.9");
        if (style == 3) {
            return string.concat(_rect(10, y - 1, 1, 3, eye, "0.9"), _rect(13, y - 1, 1, 3, eye, "0.9"));
        }
        if (style == 4) {
            return string.concat(
                _rect(9, y, 1, 1, eye, "1"),
                _rect(10, y, 1, 1, body, "0.5"),
                _rect(13, y, 1, 1, eye, "1"),
                _rect(12, y - 1, 1, 1, eye, "0.6"),
                _rect(12, y + 1, 1, 1, eye, "0.6")
            );
        }
        if (style == 5) return string.concat(_rect(9, y, 2, 1, eye, "0.8"), _rect(13, y, 2, 1, eye, "0.8"));
        if (style == 6) {
            return string.concat(_rect(10, y, 1, 1, eye, "1"), _rect(13, y, 1, 1, eye, "1"), _rect(9, y, 3, 1, eye, "0.5"));
        }
        return string.concat(_rect(10, y, 1, 1, eye, "1"), _rect(13, y, 1, 1, eye, "1"));
    }

    function _wingsLeft(uint256 style, string memory c, uint256 mixed) private pure returns (string memory) {
        uint256 yOff = _pick(mixed, 9, 3);
        if (style == 1) {
            return string.concat(_rect(4, 9 + yOff, 5, 1, c, "0.8"), _rect(3, 10 + yOff, 6, 1, c, "0.5"));
        }
        if (style == 2) {
            return string.concat(
                _rect(1, 7 + yOff, 7, 1, c, "0.95"),
                _rect(0, 8 + yOff, 8, 1, c, "0.85"),
                _rect(0, 9 + yOff, 8, 1, c, "0.75"),
                _rect(1, 10 + yOff, 7, 1, c, "0.65"),
                _rect(2, 11 + yOff, 6, 1, c, "0.55"),
                _rect(3, 12 + yOff, 5, 1, c, "0.4"),
                _rect(4, 13 + yOff, 4, 1, c, "0.25")
            );
        }
        if (style == 3) {
            return string.concat(
                _rect(0, 9 + yOff, 9, 1, c, "0.9"),
                _rect(1, 10 + yOff, 8, 1, c, "0.7"),
                _rect(2, 11 + yOff, 5, 1, c, "0.5")
            );
        }
        if (style == 4) {
            return string.concat(_rect(2, 10 + yOff, 6, 1, c, "0.6"), _rect(3, 11 + yOff, 4, 1, c, "0.35"));
        }
        return string.concat(
            _rect(2, 8 + yOff, 6, 1, c, "0.9"),
            _rect(1, 9 + yOff, 7, 1, c, "0.75"),
            _rect(0, 10 + yOff, 8, 1, c, "0.6"),
            _rect(1, 11 + yOff, 7, 1, c, "0.45"),
            _rect(2, 12 + yOff, 6, 1, c, "0.3")
        );
    }

    function _wingsRight(uint256 style, string memory c, uint256 mixed) private pure returns (string memory) {
        uint256 yOff = _pick(mixed, 9, 3);
        if (style == 1) {
            return string.concat(_rect(15, 9 + yOff, 5, 1, c, "0.8"), _rect(15, 10 + yOff, 6, 1, c, "0.5"));
        }
        if (style == 2) {
            return string.concat(
                _rect(16, 7 + yOff, 7, 1, c, "0.95"),
                _rect(16, 8 + yOff, 8, 1, c, "0.85"),
                _rect(16, 9 + yOff, 8, 1, c, "0.75"),
                _rect(16, 10 + yOff, 7, 1, c, "0.65"),
                _rect(16, 11 + yOff, 6, 1, c, "0.55"),
                _rect(16, 12 + yOff, 5, 1, c, "0.4"),
                _rect(16, 13 + yOff, 4, 1, c, "0.25")
            );
        }
        if (style == 3) {
            return string.concat(
                _rect(15, 9 + yOff, 5, 1, c, "0.5"),
                _rect(16, 10 + yOff, 7, 1, c, "0.7"),
                _rect(15, 11 + yOff, 9, 1, c, "0.9")
            );
        }
        if (style == 4) {
            return string.concat(_rect(16, 10 + yOff, 6, 1, c, "0.6"), _rect(17, 11 + yOff, 4, 1, c, "0.35"));
        }
        return string.concat(
            _rect(16, 8 + yOff, 6, 1, c, "0.9"),
            _rect(16, 9 + yOff, 7, 1, c, "0.75"),
            _rect(16, 10 + yOff, 8, 1, c, "0.6"),
            _rect(16, 11 + yOff, 7, 1, c, "0.45"),
            _rect(16, 12 + yOff, 6, 1, c, "0.3")
        );
    }

    function _accessory(uint256 kind, string memory color, uint256 mixed) private pure returns (string memory) {
        uint256 side = _pick(mixed, 10, 2);
        if (kind == 0) return "";
        if (kind == 1) {
            uint256 x = side == 0 ? 17 : 6;
            return string.concat(
                _rect(x, 12, 1, 5, color, "0.85"),
                _rect(x - 1, 11, 3, 1, color, "0.7")
            );
        }
        if (kind == 2) {
            uint256 x = side == 0 ? 18 : 5;
            return string.concat(_rect(x, 11, 2, 2, color, "0.9"), _rect(x, 13, 1, 1, color, "0.5"));
        }
        return string.concat(_rect(11, 14, 2, 3, color, "0.7"), _rect(10, 15, 4, 1, color, "0.5"));
    }

    function _robeStripe(string memory body, string memory accent, uint256 mixed) private pure returns (string memory) {
        body;
        if (_pick(mixed, 12, 3) == 0) return "";
        return _rect(11, 10, 2, 8, accent, "0.45");
    }

    function _particles(string memory halo, string memory eye, uint256 mixed, bool aura)
        private
        pure
        returns (string memory)
    {
        if (!aura) return "";
        string memory out = "";
        for (uint256 i = 0; i < 6; i++) {
            uint256 px = 2 + _pick(mixed, 11 + i, 20);
            uint256 py = 2 + _pick(mixed, 17 + (i % 3), 18);
            string memory c = i % 2 == 0 ? halo : eye;
            uint256 opNum = 25 + (i % 4) * 12;
            out = string.concat(out, _rect(px, py, 1, 1, c, _opStr(opNum)));
        }
        return out;
    }

    function _opStr(uint256 opNum) private pure returns (string memory) {
        if (opNum == 25) return "0.25";
        if (opNum == 37) return "0.37";
        if (opNum == 49) return "0.49";
        if (opNum == 61) return "0.61";
        return "0.37";
    }
}
