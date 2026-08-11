// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "./PearlTiers.sol";

/// @title On-chain pixel-art SVG renderer for Pearl Block Heroes
/// @notice 16×16 sprite. Pure on-chain. Deterministic from tokenId via keccak256.
library PearlSVGRenderer {
    using Strings for uint256;

    // Viewbox: 512×512. Sprite area: 16×16 at 24px = 384px sprite, centered with 64px margin
    // Pixel size: 24px. Sprite origin: (64, 64)

    /// @notice External entry — deployed library, called via DELEGATECALL from main contract.
    /// @dev Making this public moves all sub-functions into the library's deployed bytecode,
    ///      dropping the main contract size by ~10–12 KB.
    function tokenURI(uint256 blockNumber) public pure returns (string memory) {
        bytes32 seed = keccak256(abi.encodePacked(blockNumber, "PEARL_BLOCK_HERO_V1"));
        PearlTiers.Tier tier = PearlTiers.classify(blockNumber);

        string memory svg = _renderSVG(blockNumber, seed, tier);
        string memory attrs = _renderAttributes(seed, tier);

        string memory json = string(abi.encodePacked(
            '{"name":"Pearl Block #', blockNumber.toString(),
            '","description":"Pearl Block Heroes #', blockNumber.toString(),
            ' - pixel-art on-chain hero commemorating Pearl chain block ', blockNumber.toString(),
            '. Pure on-chain SVG, deterministic from block number.","image":"data:image/svg+xml;base64,',
            Base64.encode(bytes(svg)),
            '","attributes":', attrs, "}"
        ));

        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(bytes(json))));
    }

    // ---------- SVG composition ----------

    struct Style {
        string bg;       // background base
        string bgDot;    // background subtle dot
        string skin;     // face skin
        string skinDk;   // skin shadow
        string body;     // body/torso
        string bodyDk;   // body shadow
        string eye;      // eye color
        string accent;   // accent / mouth / accessory
        string hat1;     // hat primary
        string hat2;     // hat secondary
    }

    function _renderSVG(uint256 blockNumber, bytes32 seed, PearlTiers.Tier tier)
        private pure returns (string memory)
    {
        Style memory s = _buildStyle(seed, tier);
        uint8 eyeStyle  = uint8(seed[10]) % 4;
        uint8 mouthStyle= uint8(seed[11]) % 3;
        uint8 bgStyle   = uint8(seed[12]) % 4;

        return string(abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" shape-rendering="crispEdges">',
            // bg fill + subtle pattern
            '<rect width="512" height="512" fill="', s.bg, '"/>',
            _bgPattern(bgStyle, s.bgDot),
            // hero composed of pixel rects
            _hero(s, eyeStyle, mouthStyle, tier),
            // pixel-style frame
            _frame(tier, s.accent),
            // label
            _label(blockNumber, tier, s.skin),
            "</svg>"
        ));
    }

    // ---------- Color selection ----------

    function _buildStyle(bytes32 seed, PearlTiers.Tier tier) private pure returns (Style memory s) {
        uint8 paletteIdx = uint8(seed[0]) % 8;
        uint8 skinIdx    = uint8(seed[1]) % 5;
        uint8 bodyIdx    = uint8(seed[2]) % 6;
        uint8 eyeIdx     = uint8(seed[3]) % 4;

        // background palette (deep-sea themed)
        if (paletteIdx == 0) { s.bg = "#0b1a3a"; s.bgDot = "#1a3a6a"; s.accent = "#4dd0ff"; }
        else if (paletteIdx == 1) { s.bg = "#1a0a2e"; s.bgDot = "#3d2360"; s.accent = "#c79bff"; }
        else if (paletteIdx == 2) { s.bg = "#002424"; s.bgDot = "#055050"; s.accent = "#3cf0c0"; }
        else if (paletteIdx == 3) { s.bg = "#180826"; s.bgDot = "#3a134f"; s.accent = "#ff6fa9"; }
        else if (paletteIdx == 4) { s.bg = "#0d1f0d"; s.bgDot = "#1f4a2a"; s.accent = "#84e288"; }
        else if (paletteIdx == 5) { s.bg = "#1f0d0a"; s.bgDot = "#4a1f15"; s.accent = "#ff9a44"; }
        else if (paletteIdx == 6) { s.bg = "#0a1929"; s.bgDot = "#173a5e"; s.accent = "#5ad5f0"; }
        else { s.bg = "#161616"; s.bgDot = "#2a2a2a"; s.accent = "#e0e0e0"; }

        // skin tones (pearl-like, ranging from pale to peach to teal)
        if (skinIdx == 0) { s.skin = "#f3e4cc"; s.skinDk = "#c9b394"; }      // pale ivory
        else if (skinIdx == 1) { s.skin = "#e8c69a"; s.skinDk = "#b89360"; } // tan
        else if (skinIdx == 2) { s.skin = "#d4a576"; s.skinDk = "#9c7140"; } // bronze
        else if (skinIdx == 3) { s.skin = "#a8e0d4"; s.skinDk = "#5fa298"; } // mer-teal
        else { s.skin = "#d4b3e8"; s.skinDk = "#8a6a9c"; }                    // mystic violet

        // body / clothing
        if (bodyIdx == 0) { s.body = "#3a5a8c"; s.bodyDk = "#1f3559"; }
        else if (bodyIdx == 1) { s.body = "#6b3a8c"; s.bodyDk = "#3f1f59"; }
        else if (bodyIdx == 2) { s.body = "#3a8c5a"; s.bodyDk = "#1f593a"; }
        else if (bodyIdx == 3) { s.body = "#8c5a3a"; s.bodyDk = "#593a1f"; }
        else if (bodyIdx == 4) { s.body = "#8c3a4f"; s.bodyDk = "#591f30"; }
        else { s.body = "#4a4a4a"; s.bodyDk = "#2a2a2a"; }

        // eye color
        if (eyeIdx == 0) s.eye = "#0a0a0a";
        else if (eyeIdx == 1) s.eye = "#4dd0ff";
        else if (eyeIdx == 2) s.eye = "#ff6fa9";
        else s.eye = "#3cf0c0";

        // hat based on tier
        if (tier == PearlTiers.Tier.Legendary) { s.hat1 = "#ffd700"; s.hat2 = "#b8860b"; }
        else if (tier == PearlTiers.Tier.Epic) { s.hat1 = "#d0d0d0"; s.hat2 = "#707070"; }
        else if (tier == PearlTiers.Tier.Rare) { s.hat1 = s.accent;  s.hat2 = s.bodyDk;   }
        else                                   { s.hat1 = s.body;    s.hat2 = s.bodyDk;   }
    }

    // ---------- Hero sprite (16x16 grid, 24px pixels, origin 64,64) ----------

    function _hero(Style memory s, uint8 eyeStyle, uint8 mouthStyle, PearlTiers.Tier tier)
        private pure returns (string memory)
    {
        return string(abi.encodePacked(
            _hat(s, tier),
            _face(s),
            _eyes(s, eyeStyle),
            _mouth(s, mouthStyle),
            _body(s),
            _legs(s)
        ));
    }

    /// @dev Emits a single pixel rect at grid (col, row), each 24px.
    function _px(uint256 col, uint256 row, string memory color) private pure returns (string memory) {
        // origin: x = 64 + col*24, y = 64 + row*24
        return string(abi.encodePacked(
            '<rect x="', (64 + col * 24).toString(),
            '" y="', (64 + row * 24).toString(),
            '" width="24" height="24" fill="', color, '"/>'
        ));
    }

    /// @dev Emits a rect spanning multiple columns at a row (width = w cells).
    function _pxRow(uint256 col, uint256 row, uint256 w, string memory color) private pure returns (string memory) {
        return string(abi.encodePacked(
            '<rect x="', (64 + col * 24).toString(),
            '" y="', (64 + row * 24).toString(),
            '" width="', (w * 24).toString(),
            '" height="24" fill="', color, '"/>'
        ));
    }

    function _hat(Style memory s, PearlTiers.Tier tier) private pure returns (string memory) {
        if (tier == PearlTiers.Tier.Legendary) {
            // 5-point golden crown
            return string(abi.encodePacked(
                // crown base (row 1, cols 4-11)
                _pxRow(4, 1, 8, s.hat1),
                // crown points (row 0): cols 4, 6, 8, 10
                _px(4, 0, s.hat1), _px(6, 0, s.hat1), _px(8, 0, s.hat1), _px(10, 0, s.hat1),
                // jewel in the middle (row 1, col 7)
                _px(7, 1, s.accent),
                // shadow line under crown
                _pxRow(4, 2, 8, s.hat2)
            ));
        }
        if (tier == PearlTiers.Tier.Epic) {
            // helmet (rounded top, brim)
            return string(abi.encodePacked(
                _pxRow(5, 0, 6, s.hat1),    // top
                _pxRow(4, 1, 8, s.hat1),    // wider
                _pxRow(4, 2, 8, s.hat2),    // brim shadow
                _px(7, 0, s.accent)          // small ornament
            ));
        }
        if (tier == PearlTiers.Tier.Rare) {
            // hood / cap
            return string(abi.encodePacked(
                _pxRow(5, 1, 6, s.hat1),
                _pxRow(4, 2, 8, s.hat2)
            ));
        }
        // Common: simple bandana / minimal hat
        return string(abi.encodePacked(
            _pxRow(5, 2, 6, s.hat1)
        ));
    }

    function _face(Style memory s) private pure returns (string memory) {
        // Face block: rows 3-6, cols 5-10
        return string(abi.encodePacked(
            _pxRow(5, 3, 6, s.skin),
            _pxRow(5, 4, 6, s.skin),
            _pxRow(5, 5, 6, s.skin),
            _pxRow(5, 6, 6, s.skin),
            // chin shadow (row 7)
            _pxRow(6, 7, 4, s.skinDk)
        ));
    }

    function _eyes(Style memory s, uint8 style) private pure returns (string memory) {
        // Eye row 4 (with optional row 5 for taller styles)
        // Left eye area: cols 5-6 | Right eye area: cols 9-10 | Cols 7-8 = nose/gap

        if (style == 0) {
            // Wide bold eyes — 2 px wide solid blocks (classic chunky pixel-art look)
            // Looks like real eyes on the face, not a line.
            return string(abi.encodePacked(
                _px(5, 4, s.eye), _px(6, 4, s.eye),
                _px(9, 4, s.eye), _px(10, 4, s.eye)
            ));
        }
        if (style == 1) {
            // Sparkle eyes — 2x2 area with eye-white + pupil
            // Gives a "round/cute" expression with eye-whites
            return string(abi.encodePacked(
                // left eye: white top, pupil bottom-left, white bottom-right
                _px(5, 4, "#fefcf3"), _px(6, 4, "#fefcf3"),
                _px(5, 5, s.eye),      _px(6, 5, "#fefcf3"),
                // right eye: mirror — white top, white bottom-left, pupil bottom-right
                _px(9, 4, "#fefcf3"), _px(10, 4, "#fefcf3"),
                _px(9, 5, "#fefcf3"), _px(10, 5, s.eye)
            ));
        }
        if (style == 2) {
            // Sunglasses / visor — solid band across eye line (cool variation)
            return _pxRow(5, 4, 6, s.eye);
        }
        // Style 3: Determined — narrower bold eyes (1 px each, with a brow above)
        return string(abi.encodePacked(
            _px(5, 3, s.eye), _px(6, 3, s.eye),    // left brow
            _px(9, 3, s.eye), _px(10, 3, s.eye),   // right brow
            _px(6, 4, s.eye),                       // left pupil
            _px(9, 4, s.eye)                        // right pupil
        ));
    }

    function _mouth(Style memory s, uint8 style) private pure returns (string memory) {
        // Row 6, cols 6-9 area
        if (style == 0) {
            // small smile
            return string(abi.encodePacked(
                _px(7, 6, s.accent),
                _px(8, 6, s.accent)
            ));
        }
        if (style == 1) {
            // wide grin
            return _pxRow(6, 6, 4, s.accent);
        }
        // stoic — single px
        return _px(7, 6, s.skinDk);
    }

    function _body(Style memory s) private pure returns (string memory) {
        // Body: rows 8-12, cols 4-11
        return string(abi.encodePacked(
            _pxRow(5, 8, 6, s.body),
            _pxRow(4, 9, 8, s.body),
            _pxRow(4, 10, 8, s.body),
            // accent stripe / belt at row 11
            _pxRow(4, 11, 8, s.bodyDk),
            // buttons / pearl
            _px(7, 9, s.accent),
            _px(8, 9, s.accent),
            // lower body
            _pxRow(4, 12, 8, s.body)
        ));
    }

    function _legs(Style memory s) private pure returns (string memory) {
        // Rows 13-14, cols 4-5 and 10-11 (two legs)
        return string(abi.encodePacked(
            _pxRow(4, 13, 3, s.bodyDk),
            _pxRow(9, 13, 3, s.bodyDk),
            // feet (row 14)
            _pxRow(4, 14, 3, s.body),
            _pxRow(9, 14, 3, s.body)
        ));
    }

    // ---------- Background pattern (subtle pixel stars / waves) ----------

    function _bgPattern(uint8 style, string memory dot) private pure returns (string memory) {
        if (style == 0) {
            // sparse pixel stars
            return string(abi.encodePacked(
                '<g fill="', dot, '" opacity="0.55">',
                '<rect x="50" y="80" width="8" height="8"/>',
                '<rect x="120" y="40" width="6" height="6"/>',
                '<rect x="430" y="60" width="8" height="8"/>',
                '<rect x="470" y="180" width="6" height="6"/>',
                '<rect x="30" y="230" width="6" height="6"/>',
                '<rect x="450" y="380" width="8" height="8"/>',
                '<rect x="40" y="410" width="6" height="6"/>',
                '<rect x="380" y="430" width="6" height="6"/>',
                '<rect x="100" y="450" width="8" height="8"/>',
                "</g>"
            ));
        }
        if (style == 1) {
            // bubble columns on the sides
            return string(abi.encodePacked(
                '<g fill="', dot, '" opacity="0.4">',
                '<rect x="20" y="100" width="12" height="12"/>',
                '<rect x="36" y="160" width="8" height="8"/>',
                '<rect x="24" y="220" width="10" height="10"/>',
                '<rect x="40" y="290" width="6" height="6"/>',
                '<rect x="20" y="360" width="12" height="12"/>',
                '<rect x="468" y="120" width="10" height="10"/>',
                '<rect x="480" y="200" width="8" height="8"/>',
                '<rect x="468" y="270" width="12" height="12"/>',
                '<rect x="478" y="350" width="6" height="6"/>',
                "</g>"
            ));
        }
        if (style == 2) {
            // bottom wave pixels
            return string(abi.encodePacked(
                '<g fill="', dot, '" opacity="0.5">',
                '<rect x="0" y="460" width="24" height="12"/>',
                '<rect x="48" y="464" width="24" height="8"/>',
                '<rect x="96" y="460" width="24" height="12"/>',
                '<rect x="144" y="466" width="24" height="6"/>',
                '<rect x="192" y="460" width="24" height="12"/>',
                '<rect x="240" y="464" width="24" height="8"/>',
                '<rect x="288" y="460" width="24" height="12"/>',
                '<rect x="336" y="466" width="24" height="6"/>',
                '<rect x="384" y="460" width="24" height="12"/>',
                '<rect x="432" y="464" width="24" height="8"/>',
                '<rect x="480" y="460" width="32" height="12"/>',
                "</g>"
            ));
        }
        // dense pixel grid (corners only)
        return string(abi.encodePacked(
            '<g fill="', dot, '" opacity="0.3">',
            '<rect x="30" y="30" width="8" height="8"/><rect x="50" y="30" width="8" height="8"/>',
            '<rect x="30" y="50" width="8" height="8"/>',
            '<rect x="454" y="30" width="8" height="8"/><rect x="474" y="30" width="8" height="8"/>',
            '<rect x="474" y="50" width="8" height="8"/>',
            '<rect x="30" y="454" width="8" height="8"/><rect x="30" y="474" width="8" height="8"/>',
            '<rect x="50" y="474" width="8" height="8"/>',
            '<rect x="454" y="474" width="8" height="8"/><rect x="474" y="474" width="8" height="8"/>',
            '<rect x="474" y="454" width="8" height="8"/>',
            "</g>"
        ));
    }

    // ---------- Frame (pixel border) ----------

    function _frame(PearlTiers.Tier tier, string memory accent) private pure returns (string memory) {
        if (tier == PearlTiers.Tier.Legendary) {
            // chunky gold double frame
            return string(abi.encodePacked(
                '<g fill="#ffd700">',
                '<rect x="0" y="0" width="512" height="8"/><rect x="0" y="504" width="512" height="8"/>',
                '<rect x="0" y="0" width="8" height="512"/><rect x="504" y="0" width="8" height="512"/>',
                "</g>",
                '<g fill="#b8860b">',
                '<rect x="8" y="8" width="496" height="4"/><rect x="8" y="500" width="496" height="4"/>',
                '<rect x="8" y="8" width="4" height="496"/><rect x="500" y="8" width="4" height="496"/>',
                "</g>"
            ));
        }
        return string(abi.encodePacked(
            '<g fill="', accent, '" opacity="0.85">',
            '<rect x="0" y="0" width="512" height="6"/><rect x="0" y="506" width="512" height="6"/>',
            '<rect x="0" y="0" width="6" height="512"/><rect x="506" y="0" width="6" height="512"/>',
            "</g>"
        ));
    }

    function _label(uint256 blockNumber, PearlTiers.Tier tier, string memory color)
        private pure returns (string memory)
    {
        return string(abi.encodePacked(
            '<text x="20" y="498" fill="', color,
            '" font-family="monospace" font-size="14" font-weight="bold">#', blockNumber.toString(), '</text>',
            '<text x="492" y="498" text-anchor="end" fill="', color,
            '" font-family="monospace" font-size="11" opacity="0.85">', _tierLabel(tier), '</text>'
        ));
    }

    function _tierLabel(PearlTiers.Tier tier) private pure returns (string memory) {
        if (tier == PearlTiers.Tier.Legendary) return "LEGENDARY";
        if (tier == PearlTiers.Tier.Epic)      return "EPIC";
        if (tier == PearlTiers.Tier.Rare)      return "RARE";
        return "COMMON";
    }

    // ---------- Attributes JSON ----------

    function _renderAttributes(bytes32 seed, PearlTiers.Tier tier) private pure returns (string memory) {
        uint8 paletteIdx = uint8(seed[0]) % 8;
        uint8 skinIdx    = uint8(seed[1]) % 5;
        uint8 bodyIdx    = uint8(seed[2]) % 6;
        uint8 eyeIdx     = uint8(seed[3]) % 4;
        uint8 eyeStyle   = uint8(seed[10]) % 4;
        uint8 mouthStyle = uint8(seed[11]) % 3;
        uint8 bgStyle    = uint8(seed[12]) % 4;

        return string(abi.encodePacked(
            "[",
            '{"trait_type":"Tier","value":"',        _tierLabel(tier),     '"},',
            '{"trait_type":"Palette","value":"',     _paletteName(paletteIdx), '"},',
            '{"trait_type":"Skin","value":"',        _skinName(skinIdx),   '"},',
            '{"trait_type":"Outfit","value":"',      _bodyName(bodyIdx),   '"},',
            '{"trait_type":"Eye Color","value":"',   _eyeColorName(eyeIdx),'"},',
            '{"trait_type":"Eye Style","value":"',   _eyeStyleName(eyeStyle), '"},',
            '{"trait_type":"Expression","value":"',  _mouthName(mouthStyle),'"},',
            '{"trait_type":"Background","value":"',  _bgName(bgStyle),     '"}',
            "]"
        ));
    }

    function _paletteName(uint8 i) private pure returns (string memory) {
        if (i == 0) return "Deep Ocean";
        if (i == 1) return "Amethyst Depths";
        if (i == 2) return "Bioluminescent";
        if (i == 3) return "Coral Garden";
        if (i == 4) return "Kelp Forest";
        if (i == 5) return "Sunset Trench";
        if (i == 6) return "Arctic Blue";
        return "Moonlit Silver";
    }
    function _skinName(uint8 i) private pure returns (string memory) {
        if (i == 0) return "Ivory";
        if (i == 1) return "Tan";
        if (i == 2) return "Bronze";
        if (i == 3) return "Mer Teal";
        return "Mystic Violet";
    }
    function _bodyName(uint8 i) private pure returns (string memory) {
        if (i == 0) return "Sailor Blue";
        if (i == 1) return "Royal Purple";
        if (i == 2) return "Seaweed Green";
        if (i == 3) return "Driftwood";
        if (i == 4) return "Coral Red";
        return "Slate Gray";
    }
    function _eyeColorName(uint8 i) private pure returns (string memory) {
        if (i == 0) return "Onyx";
        if (i == 1) return "Cyan";
        if (i == 2) return "Magenta";
        return "Emerald";
    }
    function _eyeStyleName(uint8 i) private pure returns (string memory) {
        if (i == 0) return "Bold";
        if (i == 1) return "Sparkle";
        if (i == 2) return "Visor";
        return "Determined";
    }
    function _mouthName(uint8 i) private pure returns (string memory) {
        if (i == 0) return "Smile";
        if (i == 1) return "Grin";
        return "Stoic";
    }
    function _bgName(uint8 i) private pure returns (string memory) {
        if (i == 0) return "Starfield";
        if (i == 1) return "Bubbles";
        if (i == 2) return "Tide";
        return "Corners";
    }
}
