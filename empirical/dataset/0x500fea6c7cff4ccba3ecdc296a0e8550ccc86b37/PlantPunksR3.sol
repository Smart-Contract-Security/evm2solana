// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract PlantPunksR3 {
    function getHatColor(uint8 idx) internal pure returns (string memory) {
        if (idx == 0) return "#ff0044";
        if (idx == 1) return "#ff6600";
        if (idx == 2) return "#ffff00";
        if (idx == 3) return "#00ff88";
        if (idx == 4) return "#00ccff";
        if (idx == 5) return "#ff00ff";
        if (idx == 6) return "#ffffff";
        return "#ff4400";
    }

    function getAccColor(uint8 idx) internal pure returns (string memory) {
        if (idx == 0) return "#ffd700";
        if (idx == 1) return "#c0c0c0";
        if (idx == 2) return "#ff6600";
        return "#00ffff";
    }

    function getEyeColor(uint8 idx) internal pure returns (string memory) {
        if (idx == 0) return "#ff0044";
        if (idx == 1) return "#ff6600";
        if (idx == 2) return "#ffff00";
        if (idx == 3) return "#00ff88";
        if (idx == 4) return "#00ccff";
        if (idx == 5) return "#ff00ff";
        if (idx == 6) return "#ffffff";
        return "#ff4400";
    }

    // Hat: 0=mohawk 1=spikes 2=crown 3=beanie 4=cap 5=halo 6=none 7=bandana
    function drawHat(uint8 style, uint8 colorIdx) public pure returns (string memory) {
        string memory col = getHatColor(colorIdx);
        string memory svg = "";
        if (style == 0) { // mohawk
            for (uint8 y = 2; y <= 6; y++) {
                svg = string(abi.encodePacked(svg,
                    '<rect x="65" y="', _ts(y*5), '" width="5" height="5" fill="', col, '"/>',
                    '<rect x="70" y="', _ts(y*5), '" width="5" height="5" fill="', col, '"/>'));
            }
        } else if (style == 1) { // spikes
            uint8[6] memory sx = [12,13,14,15,11,16];
            uint8[6] memory sy = [4,2,2,4,5,5];
            for (uint8 i = 0; i < 6; i++) {
                svg = string(abi.encodePacked(svg,
                    '<rect x="', _ts(sx[i]*5), '" y="', _ts(sy[i]*5), '" width="5" height="5" fill="', col, '"/>'));
            }
        } else if (style == 2) { // crown
            for (uint8 x = 10; x <= 18; x++) {
                svg = string(abi.encodePacked(svg,
                    '<rect x="', _ts(x*5), '" y="30" width="5" height="5" fill="#ffd700"/>'));
            }
            uint8[4] memory cx = [10,13,16,18];
            uint8[4] memory cy = [5,4,4,5];
            for (uint8 i = 0; i < 4; i++) {
                svg = string(abi.encodePacked(svg,
                    '<rect x="', _ts(cx[i]*5), '" y="', _ts(cy[i]*5), '" width="5" height="5" fill="#ffd700"/>'));
            }
        } else if (style == 3) { // beanie
            for (uint8 y = 4; y <= 7; y++) {
                for (uint8 x = 11; x <= 17; x++) {
                    svg = string(abi.encodePacked(svg,
                        '<rect x="', _ts(x*5), '" y="', _ts(y*5), '" width="5" height="5" fill="', col, '"/>'));
                }
            }
            svg = string(abi.encodePacked(svg, '<rect x="70" y="15" width="5" height="5" fill="', col, '"/>'));
        } else if (style == 4) { // cap
            for (uint8 y = 5; y <= 7; y++) {
                for (uint8 x = 10; x <= 18; x++) {
                    svg = string(abi.encodePacked(svg,
                        '<rect x="', _ts(x*5), '" y="', _ts(y*5), '" width="5" height="5" fill="', col, '"/>'));
                }
            }
            for (uint8 x = 9; x <= 13; x++) {
                svg = string(abi.encodePacked(svg,
                    '<rect x="', _ts(x*5), '" y="40" width="5" height="5" fill="', col, '"/>'));
            }
        } else if (style == 5) { // halo
            uint8[6] memory hx = [10,11,12,16,17,18];
            for (uint8 i = 0; i < 6; i++) {
                svg = string(abi.encodePacked(svg,
                    '<rect x="', _ts(hx[i]*5), '" y="20" width="5" height="5" fill="#ffd700"/>'));
            }
        } else if (style == 7) { // bandana
            for (uint8 x = 10; x <= 18; x++) {
                svg = string(abi.encodePacked(svg,
                    '<rect x="', _ts(x*5), '" y="40" width="5" height="5" fill="', col, '"/>'));
            }
            svg = string(abi.encodePacked(svg, '<rect x="70" y="35" width="5" height="5" fill="', col, '"/>'));
        }
        return svg;
    }

    // Eyes: 0=angry 1=lazy 2=wide 3=x 4=star 5=dollar 6=skull 7=heart
    function drawEyes(uint8 style, uint8 colorIdx) public pure returns (string memory) {
        string memory col = getEyeColor(colorIdx);
        string memory svg = "";
        if (style == 0) { // angry
            svg = string(abi.encodePacked(
                '<rect x="55" y="60" width="5" height="5" fill="#111111"/>',
                '<rect x="60" y="55" width="5" height="5" fill="#111111"/>',
                '<rect x="80" y="55" width="5" height="5" fill="#111111"/>',
                '<rect x="85" y="60" width="5" height="5" fill="#111111"/>'));
        } else if (style == 1) { // lazy
            svg = string(abi.encodePacked(
                '<rect x="55" y="60" width="10" height="5" fill="#111111"/>',
                '<rect x="80" y="60" width="10" height="5" fill="#111111"/>'));
        } else if (style == 3) { // x
            svg = string(abi.encodePacked(
                '<rect x="55" y="55" width="5" height="5" fill="#111111"/>',
                '<rect x="60" y="60" width="5" height="5" fill="#111111"/>',
                '<rect x="80" y="55" width="5" height="5" fill="#111111"/>',
                '<rect x="85" y="60" width="5" height="5" fill="#111111"/>'));
        } else { // wide + others
            svg = string(abi.encodePacked(
                '<rect x="55" y="55" width="10" height="5" fill="#111111"/>',
                '<rect x="80" y="55" width="10" height="5" fill="#111111"/>'));
        }
        // pupils
        svg = string(abi.encodePacked(svg,
            '<rect x="55" y="55" width="5" height="5" fill="', col, '"/>',
            '<rect x="80" y="55" width="5" height="5" fill="', col, '"/>'));
        if (style == 4) { // star
            svg = string(abi.encodePacked(svg,
                '<rect x="60" y="50" width="5" height="5" fill="', col, '"/>',
                '<rect x="85" y="50" width="5" height="5" fill="', col, '"/>'));
        } else if (style == 5) { // dollar
            svg = string(abi.encodePacked(svg,
                '<rect x="60" y="55" width="5" height="5" fill="#ffd700"/>',
                '<rect x="85" y="55" width="5" height="5" fill="#ffd700"/>'));
        } else if (style == 6) { // skull
            svg = string(abi.encodePacked(svg,
                '<rect x="55" y="60" width="5" height="5" fill="#ffffff"/>',
                '<rect x="80" y="60" width="5" height="5" fill="#ffffff"/>'));
        } else if (style == 7) { // heart
            svg = string(abi.encodePacked(svg,
                '<rect x="60" y="55" width="5" height="5" fill="#ff4466"/>',
                '<rect x="85" y="55" width="5" height="5" fill="#ff4466"/>'));
        }
        return svg;
    }

    // Mouth: 0=smirk 1=grin 2=frown 3=fangs 4=zipper 5=joint 6=tongue 7=none
    function drawMouth(uint8 style) public pure returns (string memory) {
        string memory svg = "";
        if (style == 0) { // smirk
            svg = string(abi.encodePacked(
                '<rect x="65" y="75" width="5" height="5" fill="#111111"/>',
                '<rect x="70" y="80" width="10" height="5" fill="#111111"/>'));
        } else if (style == 1) { // grin
            for (uint8 x = 11; x <= 17; x++) {
                svg = string(abi.encodePacked(svg,
                    '<rect x="', _ts(x*5), '" y="75" width="5" height="5" fill="#111111"/>'));
            }
            svg = string(abi.encodePacked(svg,
                '<rect x="55" y="70" width="5" height="5" fill="#111111"/>',
                '<rect x="85" y="70" width="5" height="5" fill="#111111"/>'));
        } else if (style == 2) { // frown
            for (uint8 x = 12; x <= 16; x++) {
                svg = string(abi.encodePacked(svg,
                    '<rect x="', _ts(x*5), '" y="75" width="5" height="5" fill="#111111"/>'));
            }
            svg = string(abi.encodePacked(svg,
                '<rect x="60" y="70" width="5" height="5" fill="#111111"/>',
                '<rect x="80" y="70" width="5" height="5" fill="#111111"/>'));
        } else if (style == 3) { // fangs
            for (uint8 x = 11; x <= 17; x++) {
                svg = string(abi.encodePacked(svg,
                    '<rect x="', _ts(x*5), '" y="75" width="5" height="5" fill="#111111"/>'));
            }
            svg = string(abi.encodePacked(svg,
                '<rect x="60" y="80" width="5" height="5" fill="#ffffff"/>',
                '<rect x="80" y="80" width="5" height="5" fill="#ffffff"/>'));
        } else if (style == 4) { // zipper
            for (uint8 x = 11; x <= 17; x++) {
                svg = string(abi.encodePacked(svg,
                    '<rect x="', _ts(x*5), '" y="75" width="5" height="5" fill="#111111"/>'));
                if ((x - 11) % 2 == 0) {
                    svg = string(abi.encodePacked(svg,
                        '<rect x="', _ts(x*5), '" y="70" width="5" height="5" fill="#888888"/>'));
                }
            }
        } else if (style == 5) { // joint
            svg = string(abi.encodePacked(
                '<rect x="65" y="75" width="5" height="5" fill="#ffffff"/>',
                '<rect x="70" y="75" width="5" height="5" fill="#f5f5f5"/>',
                '<rect x="75" y="75" width="5" height="5" fill="#ff8800"/>'));
        } else if (style == 6) { // tongue
            for (uint8 x = 12; x <= 16; x++) {
                svg = string(abi.encodePacked(svg,
                    '<rect x="', _ts(x*5), '" y="75" width="5" height="5" fill="#111111"/>'));
            }
            svg = string(abi.encodePacked(svg,
                '<rect x="70" y="80" width="5" height="10" fill="#ff4466"/>'));
        } else { // none
            for (uint8 x = 12; x <= 16; x++) {
                svg = string(abi.encodePacked(svg,
                    '<rect x="', _ts(x*5), '" y="75" width="5" height="5" fill="#111111"/>'));
            }
        }
        return svg;
    }

    // Accessory: 0=chain 1=piercing 2=glasses 3=earring 4=tattoo 5=none 6=collar 7=badge
    function drawAccessory(uint8 style, uint8 colorIdx) public pure returns (string memory) {
        string memory col = getAccColor(colorIdx);
        string memory svg = "";
        if (style == 0) { // chain
            for (uint8 x = 10; x <= 18; x++) {
                svg = string(abi.encodePacked(svg,
                    '<rect x="', _ts(x*5), '" y="90" width="5" height="5" fill="', col, '"/>'));
            }
        } else if (style == 1) { // piercing
            svg = string(abi.encodePacked(
                '<rect x="50" y="65" width="5" height="10" fill="#c0c0c0"/>'));
        } else if (style == 2) { // glasses
            for (uint8 x = 10; x <= 13; x++) {
                svg = string(abi.encodePacked(svg,
                    '<rect x="', _ts(x*5), '" y="55" width="5" height="5" fill="', col, '"/>'));
            }
            for (uint8 x = 15; x <= 18; x++) {
                svg = string(abi.encodePacked(svg,
                    '<rect x="', _ts(x*5), '" y="55" width="5" height="5" fill="', col, '"/>'));
            }
            svg = string(abi.encodePacked(svg,
                '<rect x="70" y="55" width="5" height="5" fill="', col, '"/>'));
        } else if (style == 3) { // earring
            svg = string(abi.encodePacked(
                '<rect x="45" y="65" width="5" height="10" fill="#ffd700"/>'));
        } else if (style == 4) { // tattoo
            for (uint8 y = 15; y <= 17; y++) {
                svg = string(abi.encodePacked(svg,
                    '<rect x="45" y="', _ts(y*5), '" width="5" height="5" fill="#00ccff"/>'));
            }
        } else if (style == 6) { // collar
            for (uint8 x = 11; x <= 17; x++) {
                svg = string(abi.encodePacked(svg,
                    '<rect x="', _ts(x*5), '" y="95" width="5" height="5" fill="', col, '"/>'));
            }
        } else if (style == 7) { // badge
            for (uint8 y = 17; y <= 19; y++) {
                for (uint8 x = 17; x <= 19; x++) {
                    svg = string(abi.encodePacked(svg,
                        '<rect x="', _ts(x*5), '" y="', _ts(y*5), '" width="5" height="5" fill="', col, '"/>'));
                }
            }
            svg = string(abi.encodePacked(svg, '<rect x="90" y="90" width="5" height="5" fill="#ffffff"/>'));
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

    function render(uint8 hat, uint8 hatColor, uint8 eye, uint8 eyeColor, uint8 mouth, uint8 acc, uint8 accColor)
        external pure returns (string memory) {
        return string(abi.encodePacked(
            drawHat(hat, hatColor),
            drawEyes(eye, eyeColor),
            drawMouth(mouth),
            drawAccessory(acc, accColor)
        ));
    }
}