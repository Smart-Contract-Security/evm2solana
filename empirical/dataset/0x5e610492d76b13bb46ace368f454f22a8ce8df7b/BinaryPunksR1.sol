// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

contract BinaryPunksR1 {

    // Background styles
    function drawBackground(uint8 bgStyle, uint8 bgSeed) public pure returns (string memory) {
        string memory bg = '<rect width="120" height="120" fill="#111111"/>';
        if (bgStyle == 1) {
            // grid
            string memory lines = "";
            for (uint8 i = 0; i < 40; i += 4) {
                lines = string(abi.encodePacked(lines,
                    '<line x1="', _ts(uint256(i)*3), '" y1="0" x2="', _ts(uint256(i)*3), '" y2="120" stroke="#333333" stroke-width="1"/>'));
            }
            for (uint8 j = 0; j < 40; j += 4) {
                lines = string(abi.encodePacked(lines,
                    '<line x1="0" y1="', _ts(uint256(j)*3), '" x2="120" y2="', _ts(uint256(j)*3), '" stroke="#333333" stroke-width="1"/>'));
            }
            bg = string(abi.encodePacked(bg, lines));
        } else if (bgStyle == 2) {
            // dots
            string memory dots = "";
            for (uint8 r = 1; r < 40; r += 3) {
                for (uint8 c = 1; c < 40; c += 3) {
                    dots = string(abi.encodePacked(dots,
                        '<rect x="', _ts(uint256(c)*3), '" y="', _ts(uint256(r)*3), '" width="3" height="3" fill="#333333"/>'));
                }
            }
            bg = string(abi.encodePacked(bg, dots));
        } else if (bgStyle == 3) {
            // scanlines
            string memory scan = "";
            for (uint8 j = 0; j < 40; j += 2) {
                scan = string(abi.encodePacked(scan,
                    '<rect x="0" y="', _ts(uint256(j)*3), '" width="120" height="3" fill="#222222"/>'));
            }
            bg = string(abi.encodePacked(bg, scan));
        } else if (bgStyle == 4) {
            // vertical lines
            string memory vl = "";
            for (uint8 i = 0; i < 40; i += 6) {
                vl = string(abi.encodePacked(vl,
                    '<rect x="', _ts(uint256(i)*3), '" y="0" width="3" height="120" fill="#222222"/>'));
            }
            bg = string(abi.encodePacked(bg, vl));
        }
        return bg;
    }

    // Body mask — head + neck + shoulders silhouette
    // Returns array of [row, col] pixels that are "body"
    // Hat type affects top rows
    function getBodySVG(
        string memory bin,
        uint8 rarity,
        uint8 hatType
    ) public pure returns (string memory) {
        string memory svg = "";
        // We draw pixel by pixel using the binary string
        // Body pixels defined as regions
        uint256 idx = 0;

        // HEAD rows 9-20, cols 13-26
        for (uint8 row = 9; row <= 20; row++) {
            for (uint8 col = 13; col <= 26; col++) {
                if ((col == 13 || col == 26) && (row == 9 || row == 20)) continue;
                svg = string(abi.encodePacked(svg, _bodyPixel(col, row, idx, bin, rarity)));
                idx++;
            }
        }
        // NECK rows 21-22, cols 17-22
        for (uint8 row = 21; row <= 22; row++) {
            for (uint8 col = 17; col <= 22; col++) {
                svg = string(abi.encodePacked(svg, _bodyPixel(col, row, idx, bin, rarity)));
                idx++;
            }
        }
        // BODY rows 23-33, cols 11-28
        for (uint8 row = 23; row <= 33; row++) {
            for (uint8 col = 11; col <= 28; col++) {
                if ((col == 11 || col == 28) && row == 33) continue;
                svg = string(abi.encodePacked(svg, _bodyPixel(col, row, idx, bin, rarity)));
                idx++;
            }
        }
        // ARMS left rows 23-31 cols 8-10
        for (uint8 row = 23; row <= 31; row++) {
            for (uint8 col = 8; col <= 10; col++) {
                svg = string(abi.encodePacked(svg, _bodyPixel(col, row, idx, bin, rarity)));
                idx++;
            }
        }
        // ARMS right rows 23-31 cols 29-31
        for (uint8 row = 23; row <= 31; row++) {
            for (uint8 col = 29; col <= 31; col++) {
                svg = string(abi.encodePacked(svg, _bodyPixel(col, row, idx, bin, rarity)));
                idx++;
            }
        }
        // FOREARMS left rows 29-33 cols 6-7
        for (uint8 row = 29; row <= 33; row++) {
            for (uint8 col = 6; col <= 7; col++) {
                svg = string(abi.encodePacked(svg, _bodyPixel(col, row, idx, bin, rarity)));
                idx++;
            }
        }
        // FOREARMS right rows 29-33 cols 32-33
        for (uint8 row = 29; row <= 33; row++) {
            for (uint8 col = 32; col <= 33; col++) {
                svg = string(abi.encodePacked(svg, _bodyPixel(col, row, idx, bin, rarity)));
                idx++;
            }
        }
        // HANDS left row 34 cols 5-9
        for (uint8 col = 5; col <= 9; col++) {
            svg = string(abi.encodePacked(svg, _bodyPixel(col, 34, idx, bin, rarity)));
            idx++;
        }
        // HANDS right row 34 cols 30-34
        for (uint8 col = 30; col <= 34; col++) {
            svg = string(abi.encodePacked(svg, _bodyPixel(col, 34, idx, bin, rarity)));
            idx++;
        }
        // LEGS left rows 34-39 cols 13-17
        for (uint8 row = 34; row <= 39; row++) {
            for (uint8 col = 13; col <= 17; col++) {
                svg = string(abi.encodePacked(svg, _bodyPixel(col, row, idx, bin, rarity)));
                idx++;
            }
        }
        // LEGS right rows 34-39 cols 22-26
        for (uint8 row = 34; row <= 39; row++) {
            for (uint8 col = 22; col <= 26; col++) {
                svg = string(abi.encodePacked(svg, _bodyPixel(col, row, idx, bin, rarity)));
                idx++;
            }
        }
        // FEET left row 39 cols 12-18
        for (uint8 col = 12; col <= 18; col++) {
            svg = string(abi.encodePacked(svg, _bodyPixel(col, 39, idx, bin, rarity)));
            idx++;
        }
        // FEET right row 39 cols 21-27
        for (uint8 col = 21; col <= 27; col++) {
            svg = string(abi.encodePacked(svg, _bodyPixel(col, 39, idx, bin, rarity)));
            idx++;
        }

        // HAT pixels
        svg = string(abi.encodePacked(svg, _drawHatPixels(hatType)));

        return svg;
    }

    function _bodyPixel(uint8 col, uint8 row, uint256 idx, string memory bin, uint8 rarity)
        internal pure returns (string memory) {
        bytes memory b = bytes(bin);
        uint8 bit = idx < b.length ? (uint8(b[idx % b.length]) == 0x31 ? 1 : 0) : 0;
        string memory col_str;

        if (rarity == 2) {
            // rainbow
            string[8] memory rb = ["#ff0000","#ff8800","#ffff00","#00ff00","#00ffff","#0088ff","#aa00ff","#ff00ff"];
            // approximate rainbow by row
            col_str = rb[row % 8];
        } else if (rarity == 1) {
            // corrupted — most white, some red
            uint256 h = uint256(keccak256(abi.encodePacked(idx))) % 10;
            col_str = h < 2 ? "#ff0044" : _grayFromRow(row, false);
        } else {
            // common — gradient white top to gray bottom
            col_str = idx % 8 == 0 ? "#ffffff" : _grayFromRow(row, false);
        }
        return string(abi.encodePacked(
            '<rect x="', _ts(uint256(col)*3), '" y="', _ts(uint256(row)*3),
            '" width="3" height="3" fill="', col_str, '">',
            '<title>', bit == 1 ? '1' : '0', '</title></rect>'
        ));
    }

    function _grayFromRow(uint8 row, bool inv) internal pure returns (string memory) {
        // row 0=top bright, row 39=bottom dark
        uint256 v;
        if (inv) {
            v = uint256(row) * 5 + 20;
        } else {
            v = 240 - uint256(row) * 4;
            if (v > 240) v = 240;
            if (v < 60) v = 60;
        }
        bytes memory hex_chars = "0123456789abcdef";
        bytes memory result = new bytes(7);
        result[0] = '#';
        result[1] = hex_chars[v >> 4];
        result[2] = hex_chars[v & 0xf];
        result[3] = hex_chars[v >> 4];
        result[4] = hex_chars[v & 0xf];
        result[5] = hex_chars[v >> 4];
        result[6] = hex_chars[v & 0xf];
        return string(result);
    }

    function _drawHatPixels(uint8 hatType) internal pure returns (string memory) {
        string memory h = "";
        string memory hc = "#ffffff";
        if (hatType == 0) { // mohawk
            for (uint8 r = 3; r <= 8; r++) {
                h = string(abi.encodePacked(h,
                    '<rect x="', _ts(18*3), '" y="', _ts(uint256(r)*3), '" width="12" height="3" fill="', hc, '"/>'));
            }
        } else if (hatType == 1) { // spikes
            uint8[8] memory sx = [17,18,19,20,21,22,16,23];
            uint8[8] memory sy = [5,4,3,3,4,5,6,6];
            for (uint8 i = 0; i < 8; i++) {
                h = string(abi.encodePacked(h,
                    '<rect x="', _ts(uint256(sx[i])*3), '" y="', _ts(uint256(sy[i])*3), '" width="3" height="3" fill="', hc, '"/>'));
            }
            for (uint8 c = 17; c <= 22; c++) {
                h = string(abi.encodePacked(h,
                    '<rect x="', _ts(uint256(c)*3), '" y="', _ts(7*3), '" width="3" height="6" fill="', hc, '"/>'));
            }
        } else if (hatType == 2) { // cap
            for (uint8 r = 4; r <= 9; r++) {
                for (uint8 c = 12; c <= 27; c++) {
                    h = string(abi.encodePacked(h,
                        '<rect x="', _ts(uint256(c)*3), '" y="', _ts(uint256(r)*3), '" width="3" height="3" fill="', hc, '"/>'));
                }
            }
            for (uint8 c = 8; c <= 16; c++) {
                h = string(abi.encodePacked(h,
                    '<rect x="', _ts(uint256(c)*3), '" y="', _ts(10*3), '" width="3" height="3" fill="', hc, '"/>'));
            }
        } else if (hatType == 3) { // crown
            for (uint8 c = 13; c <= 26; c++) {
                h = string(abi.encodePacked(h,
                    '<rect x="', _ts(uint256(c)*3), '" y="', _ts(8*3), '" width="3" height="3" fill="', hc, '"/>'));
            }
            uint8[5] memory cx = [13,16,19,22,25];
            uint8[5] memory cy = [7,6,5,6,7];
            for (uint8 i = 0; i < 5; i++) {
                h = string(abi.encodePacked(h,
                    '<rect x="', _ts(uint256(cx[i])*3), '" y="', _ts(uint256(cy[i])*3), '" width="3" height="3" fill="', hc, '"/>'));
            }
        } else if (hatType == 4) { // beanie
            for (uint8 r = 3; r <= 9; r++) {
                for (uint8 c = 13; c <= 26; c++) {
                    h = string(abi.encodePacked(h,
                        '<rect x="', _ts(uint256(c)*3), '" y="', _ts(uint256(r)*3), '" width="3" height="3" fill="', hc, '"/>'));
                }
            }
            h = string(abi.encodePacked(h,
                '<rect x="', _ts(18*3), '" y="', _ts(2*3), '" width="9" height="3" fill="', hc, '"/>'));
        } else if (hatType == 5) { // hood
            for (uint8 r = 3; r <= 10; r++) {
                for (uint8 c = 11; c <= 28; c++) {
                    if (c > 14 && c < 25 && r > 6) continue;
                    h = string(abi.encodePacked(h,
                        '<rect x="', _ts(uint256(c)*3), '" y="', _ts(uint256(r)*3), '" width="3" height="3" fill="', hc, '"/>'));
                }
            }
        } else if (hatType == 6) { // headset
            for (uint8 r = 5; r <= 10; r++) {
                h = string(abi.encodePacked(h,
                    '<rect x="', _ts(10*3), '" y="', _ts(uint256(r)*3), '" width="6" height="3" fill="', hc, '"/>',
                    '<rect x="', _ts(28*3), '" y="', _ts(uint256(r)*3), '" width="6" height="3" fill="', hc, '"/>'));
            }
            for (uint8 c = 12; c <= 27; c++) {
                h = string(abi.encodePacked(h,
                    '<rect x="', _ts(uint256(c)*3), '" y="', _ts(4*3), '" width="3" height="3" fill="', hc, '"/>'));
            }
        } else if (hatType == 7) { // antenna
            h = string(abi.encodePacked(h,
                '<rect x="', _ts(19*3), '" y="3" width="3" height="15" fill="', hc, '"/>',
                '<rect x="', _ts(18*3), '" y="3" width="9" height="3" fill="', hc, '"/>',
                '<rect x="', _ts(19*3), '" y="0" width="3" height="6" fill="#ffffff"/>'));
        } else if (hatType == 8) { // bandana
            for (uint8 c = 10; c <= 29; c++) {
                h = string(abi.encodePacked(h,
                    '<rect x="', _ts(uint256(c)*3), '" y="', _ts(8*3), '" width="3" height="9" fill="', hc, '"/>'));
            }
            h = string(abi.encodePacked(h,
                '<rect x="', _ts(19*3), '" y="', _ts(7*3), '" width="6" height="3" fill="', hc, '"/>'));
        }
        // hatType 9 = none
        return h;
    }

    function render(
        string memory bin,
        uint8 rarity,
        uint8 bgStyle,
        uint8 bgSeed,
        uint8 hatType
    ) external pure returns (string memory) {
        string memory bg = drawBackground(bgStyle, bgSeed);
        string memory body = getBodySVG(bin, rarity, hatType);
        return string(abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120" shape-rendering="crispEdges">',
            bg, body, '</svg>'
        ));
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
}
