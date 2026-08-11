// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

contract BinaryPunksR2 {

    // Eyes: 0=normal 1=angry 2=wide 3=x 4=heart 5=star 6=scan 7=dollar
    function drawEyes(uint8 style) public pure returns (string memory) {
        string memory s = "";
        string memory w = "#ffffff";
        string memory b = "#000000";
        string memory g = "#aaaaaa";

        // eye glow
        s = string(abi.encodePacked(s,
            '<rect x="39" y="39" width="9" height="9" fill="#ffffff11"/>',
            '<rect x="63" y="39" width="9" height="9" fill="#ffffff11"/>'));

        if (style == 0) { // normal
            s = string(abi.encodePacked(s,
                '<rect x="42" y="45" width="6" height="6" fill="', w, '"/>',
                '<rect x="66" y="45" width="6" height="6" fill="', w, '"/>',
                '<rect x="42" y="42" width="6" height="3" fill="', g, '"/>',
                '<rect x="66" y="42" width="6" height="3" fill="', g, '"/>'));
        } else if (style == 1) { // angry
            s = string(abi.encodePacked(s,
                '<rect x="42" y="45" width="6" height="6" fill="', w, '"/>',
                '<rect x="66" y="45" width="6" height="6" fill="', w, '"/>',
                '<rect x="45" y="42" width="3" height="3" fill="', b, '"/>',
                '<rect x="63" y="42" width="3" height="3" fill="', b, '"/>'));
        } else if (style == 2) { // wide
            s = string(abi.encodePacked(s,
                '<rect x="39" y="42" width="12" height="9" fill="', w, '"/>',
                '<rect x="63" y="42" width="12" height="9" fill="', w, '"/>',
                '<rect x="42" y="45" width="6" height="3" fill="', b, '"/>',
                '<rect x="66" y="45" width="6" height="3" fill="', b, '"/>'));
        } else if (style == 3) { // x eyes
            s = string(abi.encodePacked(s,
                '<rect x="42" y="42" width="3" height="3" fill="', w, '"/>',
                '<rect x="48" y="48" width="3" height="3" fill="', w, '"/>',
                '<rect x="48" y="42" width="3" height="3" fill="', w, '"/>',
                '<rect x="42" y="48" width="3" height="3" fill="', w, '"/>',
                '<rect x="66" y="42" width="3" height="3" fill="', w, '"/>',
                '<rect x="72" y="48" width="3" height="3" fill="', w, '"/>',
                '<rect x="72" y="42" width="3" height="3" fill="', w, '"/>',
                '<rect x="66" y="48" width="3" height="3" fill="', w, '"/>'));
        } else if (style == 4) { // heart
            s = string(abi.encodePacked(s,
                '<rect x="39" y="42" width="6" height="3" fill="#ff4466"/>',
                '<rect x="48" y="42" width="6" height="3" fill="#ff4466"/>',
                '<rect x="36" y="45" width="18" height="6" fill="#ff4466"/>',
                '<rect x="39" y="51" width="12" height="3" fill="#ff4466"/>',
                '<rect x="42" y="54" width="6" height="3" fill="#ff4466"/>',
                '<rect x="63" y="42" width="6" height="3" fill="#ff4466"/>',
                '<rect x="72" y="42" width="6" height="3" fill="#ff4466"/>',
                '<rect x="60" y="45" width="18" height="6" fill="#ff4466"/>',
                '<rect x="63" y="51" width="12" height="3" fill="#ff4466"/>',
                '<rect x="66" y="54" width="6" height="3" fill="#ff4466"/>'));
        } else if (style == 5) { // star
            s = string(abi.encodePacked(s,
                '<rect x="42" y="39" width="3" height="3" fill="', w, '"/>',
                '<rect x="39" y="42" width="9" height="9" fill="', w, '"/>',
                '<rect x="42" y="51" width="3" height="3" fill="', w, '"/>',
                '<rect x="66" y="39" width="3" height="3" fill="', w, '"/>',
                '<rect x="63" y="42" width="9" height="9" fill="', w, '"/>',
                '<rect x="66" y="51" width="3" height="3" fill="', w, '"/>'));
        } else if (style == 6) { // scan line
            for (uint8 c = 9; c <= 30; c++) {
                s = string(abi.encodePacked(s,
                    '<rect x="', _ts(uint256(c)*3), '" y="45" width="3" height="3" fill="', w, '"/>'));
            }
        } else { // dollar
            s = string(abi.encodePacked(s,
                '<rect x="42" y="45" width="6" height="6" fill="#ffd700"/>',
                '<rect x="66" y="45" width="6" height="6" fill="#ffd700"/>',
                '<rect x="42" y="42" width="6" height="3" fill="#aa8800"/>',
                '<rect x="66" y="42" width="6" height="3" fill="#aa8800"/>'));
        }
        // eye shine
        s = string(abi.encodePacked(s,
            '<rect x="42" y="42" width="3" height="3" fill="#ffffff"/>',
            '<rect x="66" y="42" width="3" height="3" fill="#ffffff"/>'));
        return s;
    }

    // Mouth: 0=smirk 1=grin 2=frown 3=fangs 4=zipper 5=data 6=mask 7=none
    function drawMouth(uint8 style) public pure returns (string memory) {
        string memory s = "";
        string memory w = "#ffffff";
        string memory b = "#000000";
        if (style == 0) { // smirk
            s = string(abi.encodePacked(
                '<rect x="54" y="54" width="3" height="3" fill="', w, '"/>',
                '<rect x="57" y="57" width="9" height="3" fill="', w, '"/>'));
        } else if (style == 1) { // grin
            for (uint8 c = 11; c <= 17; c++) {
                s = string(abi.encodePacked(s,
                    '<rect x="', _ts(uint256(c)*3), '" y="54" width="3" height="3" fill="', w, '"/>'));
            }
            s = string(abi.encodePacked(s,
                '<rect x="33" y="51" width="3" height="3" fill="', w, '"/>',
                '<rect x="51" y="51" width="3" height="3" fill="', w, '"/>',
                '<rect x="36" y="57" width="3" height="3" fill="#ff9999"/>',
                '<rect x="39" y="57" width="9" height="3" fill="#ff9999"/>'));
        } else if (style == 2) { // frown
            for (uint8 c = 11; c <= 17; c++) {
                s = string(abi.encodePacked(s,
                    '<rect x="', _ts(uint256(c)*3), '" y="54" width="3" height="3" fill="', w, '"/>'));
            }
            s = string(abi.encodePacked(s,
                '<rect x="33" y="57" width="3" height="3" fill="', w, '"/>',
                '<rect x="51" y="57" width="3" height="3" fill="', w, '"/>'));
        } else if (style == 3) { // fangs
            for (uint8 c = 11; c <= 17; c++) {
                s = string(abi.encodePacked(s,
                    '<rect x="', _ts(uint256(c)*3), '" y="54" width="3" height="3" fill="', w, '"/>'));
            }
            s = string(abi.encodePacked(s,
                '<rect x="36" y="57" width="3" height="6" fill="', w, '"/>',
                '<rect x="48" y="57" width="3" height="6" fill="', w, '"/>'));
        } else if (style == 4) { // zipper
            for (uint8 c = 10; c <= 18; c++) {
                s = string(abi.encodePacked(s,
                    '<rect x="', _ts(uint256(c)*3), '" y="54" width="3" height="3" fill="', w, '"/>'));
                if ((c - 10) % 2 == 0) {
                    s = string(abi.encodePacked(s,
                        '<rect x="', _ts(uint256(c)*3), '" y="51" width="3" height="3" fill="#888888"/>'));
                }
            }
        } else if (style == 5) { // data stream
            for (uint8 c = 10; c <= 18; c++) {
                string memory dc = c % 2 == 0 ? w : "#555555";
                s = string(abi.encodePacked(s,
                    '<rect x="', _ts(uint256(c)*3), '" y="54" width="3" height="3" fill="', dc, '"/>'));
            }
        } else if (style == 6) { // mask
            for (uint8 r = 17; r <= 19; r++) {
                for (uint8 c = 10; c <= 18; c++) {
                    s = string(abi.encodePacked(s,
                        '<rect x="', _ts(uint256(c)*3), '" y="', _ts(uint256(r)*3), '" width="3" height="3" fill="#1a1a1a"/>'));
                }
            }
            s = string(abi.encodePacked(s,
                '<rect x="33" y="54" width="3" height="3" fill="#333333"/>',
                '<rect x="51" y="54" width="3" height="3" fill="#333333"/>'));
        }
        // style 7 = none (just flat line)
        if (style == 7) {
            s = string(abi.encodePacked(
                '<rect x="39" y="54" width="18" height="3" fill="#555555"/>'));
        }
        return s;
    }

    // Clothes: 0=hoodie 1=jacket 2=armor 3=tshirt 4=vest 5/6/7=none
    function drawClothes(uint8 style) public pure returns (string memory) {
        string memory s = "";
        string memory c1 = "#333333";
        if (style == 0) { // hoodie
            for (uint8 r = 23; r <= 33; r++) {
                for (uint8 c = 11; c <= 28; c++) {
                    s = string(abi.encodePacked(s,
                        '<rect x="', _ts(uint256(c)*3), '" y="', _ts(uint256(r)*3), '" width="3" height="3" fill="', c1, '" opacity="0.6"/>'));
                }
            }
            for (uint8 r = 3; r <= 10; r++) {
                for (uint8 c = 11; c <= 28; c++) {
                    if (c > 15 && c < 24 && r > 6) continue;
                    s = string(abi.encodePacked(s,
                        '<rect x="', _ts(uint256(c)*3), '" y="', _ts(uint256(r)*3), '" width="3" height="3" fill="', c1, '" opacity="0.55"/>'));
                }
            }
        } else if (style == 1) { // jacket
            for (uint8 r = 23; r <= 33; r++) {
                for (uint8 c = 11; c <= 28; c++) {
                    s = string(abi.encodePacked(s,
                        '<rect x="', _ts(uint256(c)*3), '" y="', _ts(uint256(r)*3), '" width="3" height="3" fill="', c1, '" opacity="0.55"/>'));
                }
            }
            // lapels
            for (uint8 r = 23; r <= 30; r++) {
                s = string(abi.encodePacked(s,
                    '<rect x="48" y="', _ts(uint256(r)*3), '" width="3" height="3" fill="#444444"/>',
                    '<rect x="69" y="', _ts(uint256(r)*3), '" width="3" height="3" fill="#444444"/>'));
            }
        } else if (style == 2) { // armor
            for (uint8 r = 23; r <= 33; r++) {
                for (uint8 c = 11; c <= 28; c++) {
                    s = string(abi.encodePacked(s,
                        '<rect x="', _ts(uint256(c)*3), '" y="', _ts(uint256(r)*3), '" width="3" height="3" fill="#3a3a3a" opacity="0.6"/>'));
                }
            }
            for (uint8 c = 12; c <= 27; c++) {
                s = string(abi.encodePacked(s,
                    '<rect x="', _ts(uint256(c)*3), '" y="69" width="3" height="6" fill="#555555"/>'));
            }
        } else if (style == 3) { // tshirt
            for (uint8 r = 23; r <= 31; r++) {
                for (uint8 c = 12; c <= 27; c++) {
                    s = string(abi.encodePacked(s,
                        '<rect x="', _ts(uint256(c)*3), '" y="', _ts(uint256(r)*3), '" width="3" height="3" fill="', c1, '" opacity="0.5"/>'));
                }
            }
        } else if (style == 4) { // vest
            for (uint8 r = 23; r <= 33; r++) {
                for (uint8 c = 11; c <= 28; c++) {
                    if (c >= 18 && c <= 21) continue;
                    s = string(abi.encodePacked(s,
                        '<rect x="', _ts(uint256(c)*3), '" y="', _ts(uint256(r)*3), '" width="3" height="3" fill="', c1, '" opacity="0.5"/>'));
                }
            }
        }
        return s;
    }

    // Accessory: 0=chain 1=glasses 2=earring 3=piercing 4=collar 5=badge 6=usb 7=tattoo 8=chip 9=none
    function drawAccessory(uint8 style) public pure returns (string memory) {
        string memory s = "";
        string memory w = "#ffffff";
        string memory g = "#aaaaaa";
        if (style == 0) { // chain
            for (uint8 c = 14; c <= 25; c++) {
                string memory cc = c % 2 == 0 ? w : "#333333";
                s = string(abi.encodePacked(s,
                    '<rect x="', _ts(uint256(c)*3), '" y="66" width="3" height="3" fill="', cc, '"/>'));
            }
        } else if (style == 1) { // glasses
            for (uint8 c = 13; c <= 16; c++) {
                s = string(abi.encodePacked(s,
                    '<rect x="', _ts(uint256(c)*3), '" y="39" width="3" height="3" fill="', w, '"/>'));
            }
            for (uint8 c = 22; c <= 25; c++) {
                s = string(abi.encodePacked(s,
                    '<rect x="', _ts(uint256(c)*3), '" y="39" width="3" height="3" fill="', w, '"/>'));
            }
            s = string(abi.encodePacked(s,
                '<rect x="51" y="39" width="3" height="3" fill="', w, '"/>',
                '<rect x="63" y="39" width="3" height="3" fill="', w, '"/>',
                '<rect x="39" y="42" width="3" height="3" fill="', w, '"/>',
                '<rect x="48" y="42" width="3" height="3" fill="', w, '"/>',
                '<rect x="66" y="42" width="3" height="3" fill="', w, '"/>',
                '<rect x="75" y="42" width="3" height="3" fill="', w, '"/>'));
        } else if (style == 2) { // earring
            s = string(abi.encodePacked(s,
                '<rect x="36" y="36" width="3" height="6" fill="', w, '"/>',
                '<rect x="33" y="39" width="3" height="3" fill="', g, '"/>'));
        } else if (style == 3) { // piercing
            s = '<rect x="36" y="54" width="3" height="6" fill="#aaaaaa"/>';
        } else if (style == 4) { // collar
            for (uint8 c = 14; c <= 25; c++) {
                s = string(abi.encodePacked(s,
                    '<rect x="', _ts(uint256(c)*3), '" y="63" width="3" height="3" fill="', w, '"/>'));
            }
            s = string(abi.encodePacked(s,
                '<rect x="57" y="60" width="6" height="3" fill="', w, '"/>'));
        } else if (style == 5) { // badge
            s = string(abi.encodePacked(s,
                '<rect x="36" y="78" width="9" height="9" fill="', w, '"/>',
                '<rect x="39" y="81" width="3" height="3" fill="#111111"/>'));
        } else if (style == 6) { // usb
            s = string(abi.encodePacked(s,
                '<rect x="96" y="75" width="9" height="6" fill="', g, '"/>',
                '<rect x="99" y="72" width="3" height="3" fill="', w, '"/>'));
        } else if (style == 7) { // tattoo
            for (uint8 r = 29; r <= 32; r++) {
                s = string(abi.encodePacked(s,
                    '<rect x="30" y="', _ts(uint256(r)*3), '" width="3" height="3" fill="', g, '"/>',
                    '<rect x="27" y="', _ts(uint256(r)*3), '" width="3" height="3" fill="#777777"/>'));
            }
        } else if (style == 8) { // chip
            s = string(abi.encodePacked(s,
                '<rect x="81" y="78" width="9" height="9" fill="', g, '"/>',
                '<rect x="84" y="81" width="3" height="3" fill="#111111"/>',
                '<rect x="81" y="84" width="3" height="3" fill="', w, '"/>'));
        }
        return s;
    }

    function render(uint8 eye, uint8 mouth, uint8 clothes, uint8 acc)
        external pure returns (string memory) {
        return string(abi.encodePacked(
            drawClothes(clothes),
            drawEyes(eye),
            drawMouth(mouth),
            drawAccessory(acc)
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
