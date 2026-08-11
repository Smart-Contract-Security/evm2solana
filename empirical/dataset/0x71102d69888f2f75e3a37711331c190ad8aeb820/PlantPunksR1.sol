// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract PlantPunksR1 {
    // Background palettes [dark, light]
    function getBgColors(uint8 idx) internal pure returns (string memory c1, string memory c2) {
        if (idx == 0) return ("#0d0d1a", "#1a0d2e");
        if (idx == 1) return ("#0a1a0a", "#0d2b0d");
        if (idx == 2) return ("#1a0a0a", "#2b0d0d");
        if (idx == 3) return ("#0a0a1a", "#0d1a2b");
        if (idx == 4) return ("#1a1a0a", "#2b2b0d");
        if (idx == 5) return ("#1a0a1a", "#2b0d2b");
        if (idx == 6) return ("#000000", "#111111");
        return ("#0a1010", "#0d2020");
    }

    function getPlantColors(uint8 ptype) internal pure returns (
        string memory body, string memory skin, string memory dark, string memory tip
    ) {
        if (ptype == 0) return ("#2d7a2d","#3a9a3a","#1a4a1a","#8B4513"); // cactus
        if (ptype == 1) return ("#cc3333","#ff4444","#991111","#ffffff"); // shroom
        if (ptype == 2) return ("#cc8800","#ffaa00","#885500","#ff66cc"); // flower
        if (ptype == 3) return ("#cc2244","#ff3366","#881122","#33cc33"); // venus
        if (ptype == 4) return ("#1a6b1a","#2a8b2a","#0d3d0d","#88cc44"); // fern
        if (ptype == 5) return ("#4466cc","#6688ff","#223388","#aaccff"); // crystal
        if (ptype == 6) return ("#4a7a1a","#6a9a2a","#2a4a0a","#ccff44"); // moss
        return ("#4a3a2a","#6a5a3a","#2a1a0a","#888888"); // dead
    }

    // Draw background 28x28
    function drawBackground(uint8 bgStyle, uint8 bgPal) public pure returns (string memory) {
        (string memory c1, string memory c2) = getBgColors(bgPal);
        string memory rects = string(abi.encodePacked(
            '<rect width="140" height="140" fill="', c1, '"/>'
        ));
        if (bgStyle == 1) { // grid
            string memory gridRects = "";
            for (uint8 i = 0; i < 28; i += 3) {
                for (uint8 j = 0; j < 28; j += 3) {
                    if ((uint16(i) + j) % 6 == 0) {
                        gridRects = string(abi.encodePacked(gridRects,
                            '<rect x="', _ts(i*5), '" y="', _ts(j*5), '" width="5" height="5" fill="', c2, '"/>'));
                    }
                }
            }
            rects = string(abi.encodePacked(rects, gridRects));
        } else if (bgStyle == 2) { // diagonal
            string memory lines = "";
            for (uint8 i = 0; i < 56; i += 4) {
                lines = string(abi.encodePacked(lines,
                    '<rect x="0" y="', _ts(i*5), '" width="140" height="5" fill="', c2, '"/>'));
            }
            rects = string(abi.encodePacked(rects, lines));
        } else if (bgStyle == 3) { // scanline
            string memory lines = "";
            for (uint8 j = 0; j < 28; j += 2) {
                lines = string(abi.encodePacked(lines,
                    '<rect x="0" y="', _ts(j*5), '" width="140" height="5" fill="', c2, '"/>'));
            }
            rects = string(abi.encodePacked(rects, lines));
        } else if (bgStyle == 4) { // radial rings
            string memory rings = "";
            uint8[5] memory radii = [3, 6, 9, 12, 15];
            for (uint8 r = 0; r < 5; r++) {
                rings = string(abi.encodePacked(rings,
                    '<circle cx="70" cy="70" r="', _ts(radii[r]*5), '" fill="none" stroke="', c2, '" stroke-width="4"/>'));
            }
            rects = string(abi.encodePacked(rects, rings));
        } else if (bgStyle == 5) { // solid flat (cryptopunks style)
            rects = string(abi.encodePacked('<rect width="140" height="140" fill="', c1, '"/>'));
        }
        return rects;
    }

    // Draw cactus body
    function drawCactus(string memory body, string memory skin, string memory dark, string memory tip)
        public pure returns (string memory) {
        string memory svg = "";
        // arms left
        svg = string(abi.encodePacked(svg, '<rect x="30" y="35" width="5" height="15" fill="', body, '"/>'));
        svg = string(abi.encodePacked(svg, '<rect x="35" y="35" width="5" height="15" fill="', dark, '"/>'));
        svg = string(abi.encodePacked(svg, '<rect x="35" y="30" width="5" height="5" fill="', body, '"/>'));
        // arms right
        svg = string(abi.encodePacked(svg, '<rect x="100" y="35" width="5" height="15" fill="', body, '"/>'));
        svg = string(abi.encodePacked(svg, '<rect x="105" y="35" width="5" height="15" fill="', dark, '"/>'));
        svg = string(abi.encodePacked(svg, '<rect x="100" y="30" width="5" height="5" fill="', body, '"/>'));
        // main body
        for (uint8 y = 6; y <= 20; y++) {
            for (uint8 x = 10; x <= 18; x++) {
                string memory col;
                if (x == 10 || x == 18 || y == 6) col = dark;
                else if (x % 3 == 0) col = skin;
                else col = body;
                svg = string(abi.encodePacked(svg,
                    '<rect x="', _ts(x*5), '" y="', _ts(y*5), '" width="5" height="5" fill="', col, '"/>'));
            }
        }
        // spines
        uint8[6] memory sx = [9,9,9,19,19,19];
        uint8[6] memory sy = [8,12,16,8,12,16];
        for (uint8 i = 0; i < 6; i++) {
            svg = string(abi.encodePacked(svg,
                '<rect x="', _ts(sx[i]*5), '" y="', _ts(sy[i]*5), '" width="5" height="5" fill="', tip, '"/>'));
        }
        // pot
        for (uint8 y = 20; y <= 23; y++) {
            for (uint8 x = 9; x <= 19; x++) {
                string memory pc = y == 20 ? "#8B4513" : y == 23 ? "#5a2d0c" : "#a0522d";
                svg = string(abi.encodePacked(svg,
                    '<rect x="', _ts(x*5), '" y="', _ts(y*5), '" width="5" height="5" fill="', pc, '"/>'));
            }
        }
        return svg;
    }

    // Draw shroom body
    function drawShroom(string memory body, string memory skin, string memory dark, string memory tip)
        public pure returns (string memory) {
        string memory svg = "";
        // stem
        for (uint8 y = 15; y <= 22; y++) {
            for (uint8 x = 11; x <= 17; x++) {
                string memory col = (x == 11 || x == 17) ? "#dddddd" : "#f5f5f5";
                svg = string(abi.encodePacked(svg,
                    '<rect x="', _ts(x*5), '" y="', _ts(y*5), '" width="5" height="5" fill="', col, '"/>'));
            }
        }
        // cap
        for (uint8 y = 5; y <= 15; y++) {
            uint8 w = 4 + (10 - (y > 10 ? y - 10 : 10 - y));
            uint8 sx2 = 14 - w;
            for (uint8 x = sx2; x <= sx2 + w * 2; x++) {
                string memory col = (x == sx2 || x == sx2 + w*2) ? dark : (((uint16(x)+y) % 3 == 0) ? skin : body);
                svg = string(abi.encodePacked(svg,
                    '<rect x="', _ts(x*5), '" y="', _ts(y*5), '" width="5" height="5" fill="', col, '"/>'));
            }
        }
        // spots
        uint8[5] memory spotX = [13,16,11,18,14];
        uint8[5] memory spotY = [8,7,11,10,12];
        for (uint8 i = 0; i < 5; i++) {
            svg = string(abi.encodePacked(svg,
                '<rect x="', _ts(spotX[i]*5), '" y="', _ts(spotY[i]*5), '" width="10" height="5" fill="', tip, '"/>'));
        }
        // pot
        for (uint8 y = 22; y <= 24; y++) {
            for (uint8 x = 9; x <= 19; x++) {
                svg = string(abi.encodePacked(svg,
                    '<rect x="', _ts(x*5), '" y="', _ts(y*5), '" width="5" height="5" fill="#8B4513"/>'));
            }
        }
        return svg;
    }

    // Draw flower body
    function drawFlower(string memory body, string memory skin, string memory dark, string memory tip)
        public pure returns (string memory) {
        string memory svg = "";
        // stem
        for (uint8 y = 14; y <= 22; y++) {
            svg = string(abi.encodePacked(svg,
                '<rect x="70" y="', _ts(y*5), '" width="5" height="5" fill="#2d7a2d"/>'));
        }
        // leaves
        for (uint8 i = 0; i < 3; i++) {
            svg = string(abi.encodePacked(svg,
                '<rect x="65" y="', _ts((16+i)*5), '" width="5" height="5" fill="#3a9a3a"/>',
                '<rect x="75" y="', _ts((15+i)*5), '" width="5" height="5" fill="#3a9a3a"/>'));
        }
        // petals
        uint8[8] memory px2 = [14,12,16,11,17,12,16,14];
        uint8[8] memory py2 = [6,7,7,9,9,11,11,12];
        for (uint8 i = 0; i < 8; i++) {
            svg = string(abi.encodePacked(svg,
                '<rect x="', _ts(px2[i]*5), '" y="', _ts(py2[i]*5), '" width="5" height="5" fill="', tip, '"/>'));
        }
        // center
        for (uint8 y = 8; y <= 10; y++) {
            for (uint8 x = 13; x <= 15; x++) {
                string memory col = (x == 14 && y == 9) ? skin : body;
                svg = string(abi.encodePacked(svg,
                    '<rect x="', _ts(x*5), '" y="', _ts(y*5), '" width="5" height="5" fill="', col, '"/>'));
            }
        }
        // pot
        for (uint8 y = 22; y <= 25; y++) {
            for (uint8 x = 10; x <= 18; x++) {
                string memory pc = y == 22 ? "#8B4513" : "#a0522d";
                svg = string(abi.encodePacked(svg,
                    '<rect x="', _ts(x*5), '" y="', _ts(y*5), '" width="5" height="5" fill="', pc, '"/>'));
            }
        }
        return svg;
    }

    function _ts(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        uint256 tmp = v; uint256 len = 0;
        while (tmp > 0) { len++; tmp /= 10; }
        bytes memory buf = new bytes(len);
        tmp = v;
        for (uint256 i = len; i > 0; i--) { buf[i-1] = bytes1(uint8(48 + tmp % 10)); tmp /= 10; }
        return string(buf);
    }

    function render(uint8 ptype, uint8 bgStyle, uint8 bgPal) external pure returns (string memory) {
        string memory bg = drawBackground(bgStyle, bgPal);
        (string memory body, string memory skin, string memory dark, string memory tip) = getPlantColors(ptype);
        string memory plant = "";
        if (ptype == 0) plant = drawCactus(body, skin, dark, tip);
        else if (ptype == 1) plant = drawShroom(body, skin, dark, tip);
        else plant = drawFlower(body, skin, dark, tip);
        return string(abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 140 140" shape-rendering="crispEdges">',
            bg, plant, '</svg>'
        ));
    }
}