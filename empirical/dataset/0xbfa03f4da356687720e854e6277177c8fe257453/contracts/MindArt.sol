// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {LibString} from "./solady/utils/LibString.sol";
import {Base64} from "./solady/utils/Base64.sol";

/// @title MindArt
/// @notice On-chain Nirvana-style smiley SVG for Nevermind Ticker Mind NFTs.
library MindArt {
    using LibString for uint256;

    function svg(bytes32 seed, uint256 tokenId) internal pure returns (string memory) {
        uint256 h = uint256(seed);
        uint256 mixed = uint256(keccak256(abi.encode(seed, tokenId)));

        uint256 cx = 250;
        uint256 cy = 238 + _pick(mixed, 11, 14);
        uint256 r = 118 + _pick(mixed, 12, 28);
        uint256 sw = 5 + _pick(mixed, 13, 6);
        string memory color = _strokeColor(h, _pick(mixed, 14, 8));
        string memory bg = _bgColor(mixed);

        uint256 eyeY = 210 + _pick(mixed, 15, 28);
        uint256 eyeSpan = 20 + _pick(mixed, 16, 18);
        uint256 leftX = cx - 52 - _pick(mixed, 17, 18);
        uint256 rightX = cx + 52 + _pick(mixed, 18, 18);
        uint256 mouthY = 275 + _pick(mixed, 19, 22);

        string memory eyes = _renderEyes(h, mixed, leftX, rightX, eyeY, eyeSpan, color, sw);
        string memory mouth = _renderMouth(mixed, cx, mouthY, color, sw);
        string memory tongue = _renderTongue(h, mixed, cx, mouthY, color);
        string memory face = _renderFace(cx, cy, r, color, sw, mixed);

        string memory scratch = "";
        if (_pick(mixed, 20, 3) == 0) {
            scratch = string.concat(
                '<line x1="',
                (80 + _pick(mixed, 21, 40)).toString(),
                '" y1="',
                (120 + _pick(mixed, 22, 80)).toString(),
                '" x2="',
                (160 + _pick(mixed, 23, 40)).toString(),
                '" y2="',
                (200 + _pick(mixed, 24, 80)).toString(),
                '" stroke="',
                color,
                '" stroke-width="1" opacity="0.25"/>'
            );
        }

        uint256 gf = 7 + _pick(mixed, 25, 5);
        string memory bf = gf >= 10
            ? string.concat("1.", (gf - 10).toString())
            : string.concat("0.", gf.toString());
        uint256 grainOp = 12 + _pick(mixed, 26, 8);

        return string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 500 500" width="500" height="500">',
            "<defs><filter id=\"grain-",
            tokenId.toString(),
            '"><feTurbulence type="fractalNoise" baseFrequency="',
            bf,
            '" numOctaves="4" stitchTiles="stitch"/><feColorMatrix type="saturate" values="0"/></filter></defs>',
            '<rect width="500" height="500" fill="',
            bg,
            '"/>',
            '<rect width="500" height="500" filter="url(#grain-',
            tokenId.toString(),
            ')" opacity="0.',
            grainOp.toString(),
            '"/>',
            scratch,
            face,
            eyes,
            mouth,
            tongue,
            '<text x="250" y="470" text-anchor="middle" font-family="Arial Black,sans-serif" font-size="13" fill="',
            color,
            '">#',
            tokenId.toString(),
            "</text></svg>"
        );
    }

    function tokenURI(bytes32 seed, uint256 tokenId) internal pure returns (string memory) {
        uint256 mixed = uint256(keccak256(abi.encode(seed, tokenId)));
        string memory image = svg(seed, tokenId);
        string[7] memory eyeNames = ["X", "Dots", "Sleepy", "Bars", "Star", "Split", "Arc"];
        string[6] memory mouthNames = ["Wavy", "Flat", "Open", "Frown", "Zigzag", "Grin"];
        string[5] memory tongueNames = ["None", "Classic", "Long", "Oval", "Fill"];

        string memory json = string.concat(
            '{"name":"Nevermind Face #',
            tokenId.toString(),
            '","description":"Nevermind Ticker Mind on-chain smiley.","image":"data:image/svg+xml;base64,',
            Base64.encode(bytes(image)),
            '","attributes":[{"trait_type":"Eyes","value":"',
            eyeNames[_pick(mixed, 0, 7)],
            '"},{"trait_type":"Mouth","value":"',
            mouthNames[_pick(mixed, 1, 6)],
            '"},{"trait_type":"Tongue","value":"',
            tongueNames[_pick(mixed, 2, 5)],
            '"},{"trait_type":"Palette","value":"',
            _paletteName(uint256(seed)),
            '"}]}'
        );
        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    function _pick(uint256 mixed, uint256 shift, uint256 mod) private pure returns (uint256) {
        return (mixed >> (shift * 8)) % mod;
    }

    function _hsl(uint256 hue, uint256 sat, uint256 lum) private pure returns (string memory) {
        return string.concat("hsl(", hue.toString(), ",", sat.toString(), "%,", lum.toString(), "%)");
    }

    function _strokeColor(uint256 h, uint256 variant) private pure returns (string memory) {
        uint256[8] memory hues = [uint256(56), 45, 78, 28, 52, 88, 12, 0];
        uint256 hue = hues[h % 8];
        uint256 sat = variant == 7 ? 0 : 85 + ((h >> 8) % 16);
        uint256 lum = 42 + ((h >> 16) % 28);
        return _hsl(hue, sat, lum);
    }

    function _accentColor(uint256 h, uint256 mixed) private pure returns (string memory) {
        uint256[8] memory hues = [uint256(350), 10, 56, 45, 320, 30, 0, 78];
        uint256 hue = hues[_pick(mixed, 4, 6)];
        uint256 lum = 48 + _pick(mixed, 5, 22) + ((h >> 24) % 4);
        uint256 sat = hue == 0 ? 0 : 90;
        return _hsl(hue, sat, lum);
    }

    function _bgColor(uint256 mixed) private pure returns (string memory) {
        uint256 idx = _pick(mixed, 6, 6);
        if (idx == 0) return "#000000";
        if (idx == 1) return "#0a0800";
        if (idx == 2) return "#0d0d00";
        if (idx == 3) return "#050505";
        if (idx == 4) return "#120a00";
        return "#001008";
    }

    function _paletteName(uint256 h) private pure returns (string memory) {
        string[8] memory names = ["Yellow", "Gold", "Lime", "Orange", "Cream", "Acid", "Ember", "Ghost"];
        return names[h % 8];
    }

    function _xEye(uint256 x, uint256 eyeY, uint256 span, string memory color, uint256 sw)
        private
        pure
        returns (string memory)
    {
        return string.concat(
            '<line x1="',
            (x - span).toString(),
            '" y1="',
            (eyeY - span).toString(),
            '" x2="',
            (x + span).toString(),
            '" y2="',
            (eyeY + span).toString(),
            '" stroke="',
            color,
            '" stroke-width="',
            sw.toString(),
            '" stroke-linecap="round"/>',
            '<line x1="',
            (x + span).toString(),
            '" y1="',
            (eyeY - span).toString(),
            '" x2="',
            (x - span).toString(),
            '" y2="',
            (eyeY + span).toString(),
            '" stroke="',
            color,
            '" stroke-width="',
            sw.toString(),
            '" stroke-linecap="round"/>'
        );
    }

    function _renderEyes(
        uint256 h,
        uint256 mixed,
        uint256 leftX,
        uint256 rightX,
        uint256 eyeY,
        uint256 eyeSpan,
        string memory color,
        uint256 sw
    ) private pure returns (string memory) {
        uint256 eyeType = _pick(mixed, 0, 7);
        string memory eyeColor = _pick(mixed, 7, 4) == 0 ? _accentColor(h, mixed) : color;

        if (eyeType == 0) {
            return string.concat(_xEye(leftX, eyeY, eyeSpan, eyeColor, sw), _xEye(rightX, eyeY, eyeSpan, eyeColor, sw));
        }
        if (eyeType == 1) {
            uint256 dotR = 6 + _pick(mixed, 1, 8);
            return string.concat(
                '<circle cx="',
                leftX.toString(),
                '" cy="',
                eyeY.toString(),
                '" r="',
                dotR.toString(),
                '" fill="',
                eyeColor,
                '"/>',
                '<circle cx="',
                rightX.toString(),
                '" cy="',
                eyeY.toString(),
                '" r="',
                dotR.toString(),
                '" fill="',
                eyeColor,
                '"/>'
            );
        }
        if (eyeType == 2) {
            uint256 w = eyeSpan * 2;
            return string.concat(
                '<line x1="',
                (leftX - w / 2).toString(),
                '" y1="',
                eyeY.toString(),
                '" x2="',
                (leftX + w / 2).toString(),
                '" y2="',
                eyeY.toString(),
                '" stroke="',
                eyeColor,
                '" stroke-width="',
                sw.toString(),
                '" stroke-linecap="round"/>',
                '<line x1="',
                (rightX - w / 2).toString(),
                '" y1="',
                eyeY.toString(),
                '" x2="',
                (rightX + w / 2).toString(),
                '" y2="',
                eyeY.toString(),
                '" stroke="',
                eyeColor,
                '" stroke-width="',
                sw.toString(),
                '" stroke-linecap="round"/>'
            );
        }
        if (eyeType == 3) {
            uint256 barH = (eyeSpan * 16) / 10;
            return string.concat(
                '<line x1="',
                leftX.toString(),
                '" y1="',
                (eyeY - barH / 2).toString(),
                '" x2="',
                leftX.toString(),
                '" y2="',
                (eyeY + barH / 2).toString(),
                '" stroke="',
                eyeColor,
                '" stroke-width="',
                sw.toString(),
                '" stroke-linecap="round"/>',
                '<line x1="',
                rightX.toString(),
                '" y1="',
                (eyeY - barH / 2).toString(),
                '" x2="',
                rightX.toString(),
                '" y2="',
                (eyeY + barH / 2).toString(),
                '" stroke="',
                eyeColor,
                '" stroke-width="',
                sw.toString(),
                '" stroke-linecap="round"/>'
            );
        }
        if (eyeType == 4) {
            return string.concat(_starEye(leftX, eyeY, eyeSpan, eyeColor, sw), _starEye(rightX, eyeY, eyeSpan, eyeColor, sw));
        }
        if (eyeType == 5) {
            return string.concat(
                _xEye(leftX, eyeY, eyeSpan, eyeColor, sw),
                '<circle cx="',
                rightX.toString(),
                '" cy="',
                eyeY.toString(),
                '" r="',
                (5 + _pick(mixed, 2, 6)).toString(),
                '" fill="',
                eyeColor,
                '"/>'
            );
        }
        if (eyeType == 6) {
            return string.concat(_arcEye(leftX, eyeY, eyeSpan, eyeColor, sw), _arcEye(rightX, eyeY, eyeSpan, eyeColor, sw));
        }
        uint256 big = eyeSpan + 6 + _pick(mixed, 3, 10);
        return string.concat(
            _xEye(leftX, eyeY + _pick(mixed, 2, 6), big, eyeColor, sw + 1),
            _xEye(rightX, eyeY, eyeSpan, eyeColor, sw)
        );
    }

    function _starEye(uint256 x, uint256 eyeY, uint256 span, string memory color, uint256 sw)
        private
        pure
        returns (string memory)
    {
        uint256 s = (span * 85) / 100;
        uint256 sSmall = (s * 70) / 100;
        return string.concat(
            '<line x1="',
            (x - s).toString(),
            '" y1="',
            eyeY.toString(),
            '" x2="',
            (x + s).toString(),
            '" y2="',
            eyeY.toString(),
            '" stroke="',
            color,
            '" stroke-width="',
            (sw - 1).toString(),
            '" stroke-linecap="round"/>',
            '<line x1="',
            x.toString(),
            '" y1="',
            (eyeY - s).toString(),
            '" x2="',
            x.toString(),
            '" y2="',
            (eyeY + s).toString(),
            '" stroke="',
            color,
            '" stroke-width="',
            (sw - 1).toString(),
            '" stroke-linecap="round"/>',
            '<line x1="',
            (x - sSmall).toString(),
            '" y1="',
            (eyeY - sSmall).toString(),
            '" x2="',
            (x + sSmall).toString(),
            '" y2="',
            (eyeY + sSmall).toString(),
            '" stroke="',
            color,
            '" stroke-width="',
            (sw - 2).toString(),
            '" stroke-linecap="round"/>'
        );
    }

    function _arcEye(uint256 x, uint256 eyeY, uint256 span, string memory color, uint256 sw)
        private
        pure
        returns (string memory)
    {
        uint256 lift = (span * 12) / 10;
        return string.concat(
            '<path d="M ',
            (x - span).toString(),
            ",",
            eyeY.toString(),
            " Q ",
            x.toString(),
            ",",
            (eyeY - lift).toString(),
            " ",
            (x + span).toString(),
            ",",
            eyeY.toString(),
            '" fill="none" stroke="',
            color,
            '" stroke-width="',
            sw.toString(),
            '" stroke-linecap="round"/>'
        );
    }

    function _renderMouth(uint256 mixed, uint256 cx, uint256 mouthY, string memory color, uint256 sw)
        private
        pure
        returns (string memory)
    {
        uint256 mouthType = _pick(mixed, 1, 6);
        uint256 wobble = _pick(mixed, 2, 24);

        if (mouthType == 0) {
            return string.concat(
                '<path d="M ',
                (cx - 95).toString(),
                ",",
                mouthY.toString(),
                " Q ",
                (cx - 40).toString(),
                ",",
                (mouthY + 35 + wobble).toString(),
                " ",
                cx.toString(),
                ",",
                (mouthY + 10).toString(),
                " Q ",
                (cx + 55).toString(),
                ",",
                (mouthY + 45 + _pick(mixed, 3, 15)).toString(),
                " ",
                (cx + 100).toString(),
                ",",
                (mouthY - 5).toString(),
                '" fill="none" stroke="',
                color,
                '" stroke-width="',
                sw.toString(),
                '" stroke-linecap="round"/>'
            );
        }
        if (mouthType == 1) {
            uint256 tilt = mouthY + 15 + _pick(mixed, 3, 8);
            if (_pick(mixed, 3, 8) < 4) tilt -= 4;
            return string.concat(
                '<line x1="',
                (cx - 80).toString(),
                '" y1="',
                (mouthY + 15).toString(),
                '" x2="',
                (cx + 80).toString(),
                '" y2="',
                tilt.toString(),
                '" stroke="',
                color,
                '" stroke-width="',
                sw.toString(),
                '" stroke-linecap="round"/>'
            );
        }
        if (mouthType == 2) {
            return string.concat(
                '<ellipse cx="',
                cx.toString(),
                '" cy="',
                (mouthY + 20).toString(),
                '" rx="55" ry="',
                (28 + _pick(mixed, 3, 20)).toString(),
                '" fill="none" stroke="',
                color,
                '" stroke-width="',
                sw.toString(),
                '"/>'
            );
        }
        if (mouthType == 3) {
            return string.concat(
                '<path d="M ',
                (cx - 85).toString(),
                ",",
                (mouthY + 35).toString(),
                " Q ",
                cx.toString(),
                ",",
                (mouthY - 10 - wobble).toString(),
                " ",
                (cx + 85).toString(),
                ",",
                (mouthY + 35).toString(),
                '" fill="none" stroke="',
                color,
                '" stroke-width="',
                sw.toString(),
                '" stroke-linecap="round"/>'
            );
        }
        if (mouthType == 4) {
            return string.concat(
                '<path d="M ',
                (cx - 90).toString(),
                ",",
                (mouthY + 10).toString(),
                " L ",
                (cx - 64).toString(),
                ",",
                (mouthY + 10).toString(),
                " L ",
                (cx - 38).toString(),
                ",",
                (mouthY + 18 + _pick(mixed, 4, 8)).toString(),
                " L ",
                (cx - 12).toString(),
                ",",
                (mouthY + 10).toString(),
                " L ",
                (cx + 14).toString(),
                ",",
                (mouthY + 10).toString(),
                " L ",
                (cx + 40).toString(),
                ",",
                (mouthY + 18 + _pick(mixed, 4, 8)).toString(),
                " L ",
                (cx + 66).toString(),
                ",",
                (mouthY + 10).toString(),
                '" fill="none" stroke="',
                color,
                '" stroke-width="',
                (sw - 1).toString(),
                '" stroke-linecap="round" stroke-linejoin="round"/>'
            );
        }
        uint256 gap = 12 + _pick(mixed, 3, 16);
        return string.concat(
            '<path d="M ',
            (cx - 95).toString(),
            ",",
            (mouthY + 8).toString(),
            " Q ",
            (cx - gap - 20).toString(),
            ",",
            (mouthY + 40 + wobble).toString(),
            " ",
            (cx - gap).toString(),
            ",",
            (mouthY + 5).toString(),
            '" fill="none" stroke="',
            color,
            '" stroke-width="',
            sw.toString(),
            '" stroke-linecap="round"/>',
            '<path d="M ',
            (cx + gap).toString(),
            ",",
            (mouthY + 5).toString(),
            " Q ",
            (cx + gap + 20).toString(),
            ",",
            (mouthY + 40 + wobble).toString(),
            " ",
            (cx + 95).toString(),
            ",",
            (mouthY + 8).toString(),
            '" fill="none" stroke="',
            color,
            '" stroke-width="',
            sw.toString(),
            '" stroke-linecap="round"/>'
        );
    }

    function _renderTongue(uint256 h, uint256 mixed, uint256 cx, uint256 mouthY, string memory faceColor)
        private
        pure
        returns (string memory)
    {
        uint256 tongueType = _pick(mixed, 2, 5);
        if (tongueType == 0) return "";

        string memory tColor = _pick(mixed, 8, 3) == 0 ? faceColor : _accentColor(h, mixed);
        uint256 sw = 5 + _pick(mixed, 9, 4);
        uint256 lean = _pick(mixed, 10, 40);
        if (lean >= 20) lean -= 20;

        if (tongueType == 1) {
            return string.concat(
                '<path d="M ',
                (cx + 72 + lean).toString(),
                ",",
                (mouthY + 8).toString(),
                " Q ",
                (cx + 118 + lean).toString(),
                ",",
                (mouthY + 28).toString(),
                " ",
                (cx + 95 + lean).toString(),
                ",",
                (mouthY + 52).toString(),
                " Q ",
                (cx + 68 + lean).toString(),
                ",",
                (mouthY + 38).toString(),
                " ",
                (cx + 72 + lean).toString(),
                ",",
                (mouthY + 8).toString(),
                '" fill="none" stroke="',
                tColor,
                '" stroke-width="',
                sw.toString(),
                '" stroke-linejoin="round"/>'
            );
        }
        if (tongueType == 2) {
            return string.concat(
                '<path d="M ',
                (cx + 60 + lean).toString(),
                ",",
                (mouthY + 12).toString(),
                " Q ",
                (cx + 130 + lean).toString(),
                ",",
                (mouthY + 55).toString(),
                " ",
                (cx + 88 + lean).toString(),
                ",",
                (mouthY + 95).toString(),
                '" fill="none" stroke="',
                tColor,
                '" stroke-width="',
                (sw + 1).toString(),
                '" stroke-linecap="round"/>'
            );
        }
        if (tongueType == 3) {
            return string.concat(
                '<ellipse cx="',
                (cx + 85 + lean).toString(),
                '" cy="',
                (mouthY + 38).toString(),
                '" rx="22" ry="30" fill="none" stroke="',
                tColor,
                '" stroke-width="',
                sw.toString(),
                '"/>'
            );
        }
        return string.concat(
            '<path d="M ',
            (cx + 55 + lean).toString(),
            ",",
            (mouthY + 10).toString(),
            " L ",
            (cx + 105 + lean).toString(),
            ",",
            (mouthY + 45).toString(),
            " L ",
            (cx + 70 + lean).toString(),
            ",",
            (mouthY + 55).toString(),
            ' Z" fill="',
            tColor,
            '" opacity="0.85"/>'
        );
    }

    function _renderFace(uint256 cx, uint256 cy, uint256 r, string memory color, uint256 sw, uint256 mixed)
        private
        pure
        returns (string memory)
    {
        uint256 style = _pick(mixed, 5, 4);
        if (style == 1) {
            return string.concat(
                '<circle cx="',
                cx.toString(),
                '" cy="',
                cy.toString(),
                '" r="',
                (r - 8).toString(),
                '" fill="',
                color,
                '" opacity="0.08"/>',
                '<circle cx="',
                cx.toString(),
                '" cy="',
                cy.toString(),
                '" r="',
                r.toString(),
                '" fill="none" stroke="',
                color,
                '" stroke-width="',
                sw.toString(),
                '"/>'
            );
        }
        if (style == 2) {
            return string.concat(
                '<circle cx="',
                cx.toString(),
                '" cy="',
                cy.toString(),
                '" r="',
                r.toString(),
                '" fill="none" stroke="',
                color,
                '" stroke-width="',
                sw.toString(),
                '" stroke-dasharray="18 14"/>'
            );
        }
        if (style == 3) {
            uint256 innerSw = sw > 3 ? sw - 3 : 2;
            return string.concat(
                '<circle cx="',
                cx.toString(),
                '" cy="',
                cy.toString(),
                '" r="',
                r.toString(),
                '" fill="none" stroke="',
                color,
                '" stroke-width="',
                sw.toString(),
                '"/>',
                '<circle cx="',
                cx.toString(),
                '" cy="',
                cy.toString(),
                '" r="',
                (r - 18).toString(),
                '" fill="none" stroke="',
                color,
                '" stroke-width="',
                innerSw.toString(),
                '" opacity="0.45"/>'
            );
        }
        return string.concat(
            '<circle cx="',
            cx.toString(),
            '" cy="',
            cy.toString(),
            '" r="',
            r.toString(),
            '" fill="none" stroke="',
            color,
            '" stroke-width="',
            sw.toString(),
            '"/>'
        );
    }
}
