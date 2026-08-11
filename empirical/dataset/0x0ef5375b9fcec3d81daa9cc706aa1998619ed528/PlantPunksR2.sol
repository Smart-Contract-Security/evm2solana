// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract PlantPunksR2 {
    function getPlantColors(uint8 ptype) internal pure returns (
        string memory body, string memory skin, string memory dark, string memory tip
    ) {
        if (ptype == 3) return ("#cc2244","#ff3366","#881122","#33cc33"); // venus
        if (ptype == 4) return ("#1a6b1a","#2a8b2a","#0d3d0d","#88cc44"); // fern
        if (ptype == 5) return ("#4466cc","#6688ff","#223388","#aaccff"); // crystal
        if (ptype == 6) return ("#4a7a1a","#6a9a2a","#2a4a0a","#ccff44"); // moss
        return ("#4a3a2a","#6a5a3a","#2a1a0a","#888888"); // dead (7)
    }

    // Venus flytrap
    function drawVenus(string memory body, string memory skin, string memory dark, string memory tip)
        public pure returns (string memory) {
        string memory svg = "";
        // stem
        for (uint8 y = 16; y <= 23; y++) {
            svg = string(abi.encodePacked(svg,
                '<rect x="65" y="', _ts(y*5), '" width="5" height="5" fill="#2d7a2d"/>',
                '<rect x="70" y="', _ts(y*5), '" width="5" height="5" fill="#1a5a1a"/>'));
        }
        // base leaves
        for (uint8 x = 10; x <= 17; x++) {
            for (uint8 y = 18; y <= 20; y++) {
                svg = string(abi.encodePacked(svg,
                    '<rect x="', _ts(x*5), '" y="', _ts(y*5), '" width="5" height="5" fill="#3a9a3a"/>'));
            }
        }
        // trap left
        for (uint8 y = 7; y <= 16; y++) {
            for (uint8 x = 7; x <= 12; x++) {
                string memory col = (x == 7 || y == 7) ? dark : body;
                svg = string(abi.encodePacked(svg,
                    '<rect x="', _ts(x*5), '" y="', _ts(y*5), '" width="5" height="5" fill="', col, '"/>'));
            }
        }
        // trap right
        for (uint8 y = 7; y <= 16; y++) {
            for (uint8 x = 13; x <= 18; x++) {
                string memory col = (x == 18 || y == 7) ? dark : body;
                svg = string(abi.encodePacked(svg,
                    '<rect x="', _ts(x*5), '" y="', _ts(y*5), '" width="5" height="5" fill="', col, '"/>'));
            }
        }
        // teeth
        uint8[5] memory tx = [8,10,12,14,16];
        for (uint8 i = 0; i < 5; i++) {
            svg = string(abi.encodePacked(svg,
                '<rect x="', _ts(tx[i]*5), '" y="80" width="5" height="5" fill="#ffffff"/>'));
        }
        // tongue
        svg = string(abi.encodePacked(svg,
            '<rect x="60" y="75" width="10" height="5" fill="#ff6666"/>'));
        // pot
        for (uint8 y = 23; y <= 26; y++) {
            for (uint8 x = 10; x <= 17; x++) {
                svg = string(abi.encodePacked(svg,
                    '<rect x="', _ts(x*5), '" y="', _ts(y*5), '" width="5" height="5" fill="#8B4513"/>'));
            }
        }
        return svg;
    }

    // Fern
    function drawFern(string memory body, string memory skin, string memory dark, string memory tip)
        public pure returns (string memory) {
        string memory svg = "";
        // main stem
        for (uint8 y = 8; y <= 22; y++) {
            svg = string(abi.encodePacked(svg,
                '<rect x="70" y="', _ts(y*5), '" width="5" height="5" fill="', dark, '"/>'));
        }
        // fronds
        uint8[10] memory fx1 = [13,12,11,12,13,15,16,17,16,15];
        uint8[10] memory fy1 = [9,11,13,15,17,9,11,13,15,17];
        uint8[10] memory fx2 = [10,10,9,10,11,17,18,19,18,19];
        uint8[10] memory fy2 = [8,10,12,14,16,8,10,12,14,16];
        for (uint8 i = 0; i < 10; i++) {
            svg = string(abi.encodePacked(svg,
                '<rect x="', _ts(fx1[i]*5), '" y="', _ts(fy1[i]*5), '" width="5" height="5" fill="', body, '"/>',
                '<rect x="', _ts(fx2[i]*5), '" y="', _ts(fy2[i]*5), '" width="5" height="5" fill="', skin, '"/>'));
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

    // Crystal
    function drawCrystal(string memory body, string memory skin, string memory dark, string memory tip)
        public pure returns (string memory) {
        string memory svg = "";
        uint8[4] memory cx = [12,15,18,9];
        uint8[4] memory cys = [8,5,10,12];
        uint8[4] memory cw = [2,3,2,2];
        for (uint8 s = 0; s < 4; s++) {
            for (uint8 y = cys[s]; y <= 22; y++) {
                for (uint8 x = cx[s]; x <= cx[s]+cw[s]; x++) {
                    string memory col = (x == cx[s] || x == cx[s]+cw[s] || y == cys[s]) ? skin : body;
                    svg = string(abi.encodePacked(svg,
                        '<rect x="', _ts(x*5), '" y="', _ts(y*5), '" width="5" height="5" fill="', col, '"/>'));
                }
            }
            // sparkle tip
            svg = string(abi.encodePacked(svg,
                '<rect x="', _ts((cx[s]+cw[s]/2)*5), '" y="', _ts((cys[s]-1)*5), '" width="5" height="5" fill="#ffffff"/>'));
        }
        // base
        for (uint8 y = 22; y <= 24; y++) {
            for (uint8 x = 8; x <= 20; x++) {
                svg = string(abi.encodePacked(svg,
                    '<rect x="', _ts(x*5), '" y="', _ts(y*5), '" width="5" height="5" fill="', dark, '"/>'));
            }
        }
        return svg;
    }

    // Moss
    function drawMoss(string memory body, string memory skin, string memory dark, string memory tip)
        public pure returns (string memory) {
        string memory svg = "";
        for (uint8 y = 6; y <= 20; y++) {
            for (uint8 x = 6; x <= 22; x++) {
                int8 dx = int8(x) - 14;
                int8 dy = int8(y) - 13;
                int16 r2 = int16(dx)*dx + int16(dy)*dy;
                uint8 rx = x % 3;
                int16 rval = 49 + int16(int8(rx)) * 2;
                if (r2 <= rval) {
                    bool edge = r2 > rval - 3;
                    string memory col = edge ? dark : (((uint16(x)+y) % 2 == 0) ? body : skin);
                    svg = string(abi.encodePacked(svg,
                        '<rect x="', _ts(x*5), '" y="', _ts(y*5), '" width="5" height="5" fill="', col, '"/>'));
                }
            }
        }
        // moss dots
        uint8[8] memory mx = [9,11,13,15,17,10,14,16];
        uint8[8] memory my = [9,10,9,11,9,13,12,14];
        for (uint8 i = 0; i < 8; i++) {
            svg = string(abi.encodePacked(svg,
                '<rect x="', _ts(mx[i]*5), '" y="', _ts(my[i]*5), '" width="5" height="5" fill="', tip, '"/>'));
        }
        // pot
        for (uint8 y = 20; y <= 23; y++) {
            for (uint8 x = 10; x <= 18; x++) {
                svg = string(abi.encodePacked(svg,
                    '<rect x="', _ts(x*5), '" y="', _ts(y*5), '" width="5" height="5" fill="#8B4513"/>'));
            }
        }
        return svg;
    }

    // Dead plant
    function drawDead(string memory body, string memory skin, string memory dark, string memory tip)
        public pure returns (string memory) {
        string memory svg = "";
        // main stem
        for (uint8 y = 8; y <= 22; y++) {
            svg = string(abi.encodePacked(svg,
                '<rect x="70" y="', _ts(y*5), '" width="5" height="5" fill="', body, '"/>'));
        }
        // branches
        uint8[12] memory bx = [11,10,11,12,17,18,17,16,13,15,12,16];
        uint8[12] memory by = [10,11,12,8,10,11,12,8,14,14,16,16];
        for (uint8 i = 0; i < 12; i++) {
            svg = string(abi.encodePacked(svg,
                '<rect x="', _ts(bx[i]*5), '" y="', _ts(by[i]*5), '" width="5" height="5" fill="', skin, '"/>'));
        }
        // skull
        for (uint8 y = 5; y <= 8; y++) {
            for (uint8 x = 12; x <= 16; x++) {
                svg = string(abi.encodePacked(svg,
                    '<rect x="', _ts(x*5), '" y="', _ts(y*5), '" width="5" height="5" fill="#e8e0d0"/>'));
            }
        }
        svg = string(abi.encodePacked(svg,
            '<rect x="65" y="30" width="5" height="5" fill="#111111"/>',
            '<rect x="75" y="30" width="5" height="5" fill="#111111"/>',
            '<rect x="65" y="40" width="5" height="5" fill="#111111"/>',
            '<rect x="70" y="40" width="5" height="5" fill="#111111"/>',
            '<rect x="75" y="40" width="5" height="5" fill="#111111"/>'));
        // pot
        for (uint8 y = 22; y <= 25; y++) {
            for (uint8 x = 10; x <= 18; x++) {
                string memory pc = y == 22 ? "#4a3a2a" : "#3a2a1a";
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

    function render(uint8 ptype) external pure returns (string memory) {
        (string memory body, string memory skin, string memory dark, string memory tip) = getPlantColors(ptype);
        string memory plant = "";
        if (ptype == 3) plant = drawVenus(body, skin, dark, tip);
        else if (ptype == 4) plant = drawFern(body, skin, dark, tip);
        else if (ptype == 5) plant = drawCrystal(body, skin, dark, tip);
        else if (ptype == 6) plant = drawMoss(body, skin, dark, tip);
        else plant = drawDead(body, skin, dark, tip);
        return plant;
    }
}