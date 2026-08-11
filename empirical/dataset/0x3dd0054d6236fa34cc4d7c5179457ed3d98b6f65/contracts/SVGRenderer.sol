// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";

/// @title SVGRenderer
/// @notice Generates fully on-chain animated SVG art for Galaxy Seeds NFT
contract SVGRenderer {
    using Strings for uint256;
    using Strings for uint8;

    // Core colours - one assigned per token at mint
    string[6] private CORE_COLORS = [
        "#60a5fa", // ice blue
        "#fb923c", // ember orange
        "#4ade80", // mint green
        "#f472b6", // rose
        "#fbbf24", // gold
        "#a78bfa"  // lilac
    ];

    string[6] private CORE_NAMES = [
        "Ice Blue",
        "Ember Orange",
        "Mint Green",
        "Rose",
        "Gold",
        "Lilac"
    ];

    // Dot colour per core colour (slightly lighter)
    string[6] private DOT_COLORS = [
        "148,195,255",
        "253,186,116",
        "134,239,172",
        "249,168,212",
        "253,211,77",
        "196,181,253"
    ];

    struct TokenData {
        uint256 tokenId;
        bool isMutated;
        uint8 colorIndex;
        uint256 mintedAt;
        bool isSeed;
        bool isMutatedSeed;
    }

    /// @notice Render full tokenURI for a common NFT
    function renderCommon(TokenData memory data) external view returns (string memory) {
        uint256 dotsLeft = _dotsRemaining(data.mintedAt);
        string memory svg = _buildCommonSVG(data, dotsLeft);
        return _buildTokenURI(data, svg, dotsLeft);
    }

    /// @notice Render full tokenURI for a seed NFT
    function renderSeed(TokenData memory data) external pure returns (string memory) {
        string memory svg = _buildSeedSVG(data);
        return _buildSeedTokenURI(data, svg);
    }

    function _dotsRemaining(uint256 mintedAt) internal view returns (uint256) {
        uint256 daysPassed = (block.timestamp - mintedAt) / 1 days;
        if (daysPassed >= 45) return 0;
        return 45 - daysPassed;
    }

    // -------------------------------------------------------------------------
    // COMMON SVG
    // -------------------------------------------------------------------------
    function _buildCommonSVG(TokenData memory data, uint256 dotsLeft) internal view returns (string memory) {
        string memory coreColor = CORE_COLORS[data.colorIndex];
        string memory dotColor = DOT_COLORS[data.colorIndex];
        string memory mutatedStyles = data.isMutated ? _mutatedStyles() : "";
        string memory dotsSVG = _buildDots(data.tokenId, dotsLeft, dotColor);
        string memory coreSVG = data.isMutated ? _mutatedCore() : _normalCore(coreColor);
        string memory starsSVG = _buildStars(data.tokenId);

        return string(abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 500 500">',
            '<defs>',
            '<radialGradient id="bg" cx="50%" cy="50%" r="50%">',
            '<stop offset="0%" stop-color="#0a0a1a"/>',
            '<stop offset="100%" stop-color="#020208"/>',
            '</radialGradient>',
            _coreGradient(coreColor, data.isMutated),
            mutatedStyles,
            '</defs>',
            '<rect width="500" height="500" fill="url(#bg)"/>',
            starsSVG,
            dotsSVG,
            coreSVG,
            '</svg>'
        ));
    }

    function _coreGradient(string memory color, bool isMutated) internal pure returns (string memory) {
        if (isMutated) {
            return string(abi.encodePacked(
                '<radialGradient id="cg" cx="50%" cy="50%" r="50%">',
                '<stop offset="0%" stop-color="#f0e6ff">',
                '<animate attributeName="stop-color" values="#f0e6ff;#e8d5ff;#d8b4fe;#c084fc;#d8b4fe;#e8d5ff;#f0e6ff" dur="6s" repeatCount="indefinite"/>',
                '</stop>',
                '<stop offset="50%" stop-color="#a855f7">',
                '<animate attributeName="stop-color" values="#a855f7;#9333ea;#7c3aed;#6d28d9;#7c3aed;#9333ea;#a855f7" dur="6s" repeatCount="indefinite"/>',
                '</stop>',
                '<stop offset="100%" stop-color="rgba(168,85,247,0)"/>',
                '</radialGradient>'
            ));
        }
        return string(abi.encodePacked(
            '<radialGradient id="cg" cx="50%" cy="50%" r="50%">',
            '<stop offset="0%" stop-color="white"/>',
            '<stop offset="40%" stop-color="', color, '"/>',
            '<stop offset="100%" stop-color="rgba(0,0,0,0)"/>',
            '</radialGradient>'
        ));
    }

    function _mutatedStyles() internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<style>',
            '.flicker{animation:flicker 3s ease-in-out infinite;}',
            '@keyframes flicker{0%,100%{opacity:0.1;}50%{opacity:0.45;}}',
            '</style>'
        ));
    }

    function _normalCore(string memory color) internal pure returns (string memory) {
        return string(abi.encodePacked(
            // outer glow pulse
            '<circle cx="250" cy="250" r="45" fill="url(#cg)" opacity="0.3">',
            '<animate attributeName="r" values="40;52;40" dur="3s" repeatCount="indefinite"/>',
            '<animate attributeName="opacity" values="0.25;0.4;0.25" dur="3s" repeatCount="indefinite"/>',
            '</circle>',
            // main core
            '<circle cx="250" cy="250" r="16" fill="url(#cg)">',
            '<animate attributeName="r" values="14;18;14" dur="3s" repeatCount="indefinite"/>',
            '</circle>',
            // bright centre
            '<circle cx="250" cy="250" r="5" fill="white" opacity="0.9"/>'
        ));
    }

    function _mutatedCore() internal pure returns (string memory) {
        return string(abi.encodePacked(
            // outer vague halo
            '<circle cx="250" cy="250" r="48" fill="url(#cg)" opacity="0.2">',
            '<animate attributeName="r" values="42;56;42" dur="4s" repeatCount="indefinite"/>',
            '</circle>',
            // main core - same size as normal
            '<circle cx="250" cy="250" r="16" fill="url(#cg)">',
            '<animate attributeName="r" values="14;18;14" dur="4s" repeatCount="indefinite"/>',
            '</circle>',
            // mutated marker - flickering dashed ring
            '<circle cx="250" cy="250" r="26" fill="none" stroke="#c084fc" stroke-width="1.2" stroke-dasharray="4 6" class="flicker"/>',
            // bright centre
            '<circle cx="250" cy="250" r="5" fill="white" opacity="0.9"/>'
        ));
    }

    function _buildDots(uint256 tokenId, uint256 dotsLeft, string memory dotColor) internal pure returns (string memory) {
        if (dotsLeft == 0) return "";
        bytes memory dots;
        // Each dot has a deterministic position based on tokenId + index
        for (uint256 i = 0; i < dotsLeft; i++) {
            dots = abi.encodePacked(dots, _singleDot(tokenId, i, dotColor));
        }
        return string(dots);
    }

    function _singleDot(uint256 tokenId, uint256 index, string memory dotColor) internal pure returns (string memory) {
        // Deterministic position per dot
        uint256 seed = uint256(keccak256(abi.encodePacked(tokenId, index)));
        // Angle in degrees
        uint256 angle = seed % 360;
        // Distance from centre: 55-165px
        uint256 dist = 55 + (seed >> 8) % 110;
        // Size: 1.5-3.5px
        uint256 sizeTimes10 = 15 + (seed >> 16) % 20;
        // Animation duration: 4-9s (individual drift speed)
        uint256 dur = 4 + (seed >> 24) % 5;
        // Each dot drifts to a slightly different end angle
        uint256 endAngle = (angle + 3 + (seed >> 32) % 5) % 360;

        string memory sizeStr = string(abi.encodePacked(
            (sizeTimes10 / 10).toString(), ".", (sizeTimes10 % 10).toString()
        ));

        // Convert polar to cartesian (approximated for Solidity - using 8-point lookup)
        (string memory cx, string memory cy) = _polarToCartesian(250, 250, dist, angle);
        (string memory ex, string memory ey) = _polarToCartesian(250, 250, dist > 10 ? dist - 12 : 0, endAngle);

        return string(abi.encodePacked(
            '<circle cx="', cx, '" cy="', cy, '" r="', sizeStr, '" fill="rgba(', dotColor, ',0.85)">',
            '<animate attributeName="cx" values="', cx, ';', ex, ';', cx, '" dur="', dur.toString(), 's" repeatCount="indefinite"/>',
            '<animate attributeName="cy" values="', cy, ';', ey, ';', cy, '" dur="', dur.toString(), 's" repeatCount="indefinite"/>',
            '<animate attributeName="opacity" values="0.7;1;0.7" dur="', dur.toString(), 's" repeatCount="indefinite"/>',
            '</circle>'
        ));
    }

    // 16-point polar to cartesian - good enough for SVG dot placement
    function _polarToCartesian(uint256 ox, uint256 oy, uint256 r, uint256 angleDeg) internal pure returns (string memory x, string memory y) {
        // sin/cos table * 1000 for 0,22,45,67,90,112,135,157,180,202,225,247,270,292,315,337
        int256[16] memory sinT = [int256(0),383,707,924,1000,924,707,383,0,-383,-707,-924,-1000,-924,-707,-383];
        int256[16] memory cosT = [int256(1000),924,707,383,0,-383,-707,-924,-1000,-924,-707,-383,0,383,707,924];
        uint256 idx = (angleDeg * 16) / 360 % 16;
        int256 px = int256(ox) + (int256(r) * cosT[idx]) / 1000;
        int256 py = int256(oy) + (int256(r) * sinT[idx]) / 1000;
        if (px < 0) px = 0;
        if (py < 0) py = 0;
        x = uint256(px).toString();
        y = uint256(py).toString();
    }

    function _buildStars(uint256 tokenId) internal pure returns (string memory) {
        bytes memory stars;
        for (uint256 i = 0; i < 60; i++) {
            uint256 s = uint256(keccak256(abi.encodePacked(tokenId, "star", i)));
            uint256 sx = s % 500;
            uint256 sy = (s >> 16) % 500;
            // skip centre area
            int256 dx = int256(sx) - 250;
            int256 dy = int256(sy) - 250;
            if (dx*dx + dy*dy < 40000) continue;
            uint256 op = 15 + (s >> 32) % 30;
            stars = abi.encodePacked(stars,
                '<circle cx="', sx.toString(), '" cy="', sy.toString(),
                '" r="0.6" fill="rgba(200,215,255,0.', op.toString(), ')"/>'
            );
        }
        return string(stars);
    }

    // -------------------------------------------------------------------------
    // SEED SVG - Crystal Pod Side View
    // -------------------------------------------------------------------------
    function _buildSeedSVG(TokenData memory data) internal pure returns (string memory) {
        string memory hueAnim = data.isMutatedSeed
            ? "185;165;185;210;185"   // shifts more dramatically
            : "185;195;185;175;185";  // subtle calm shift

        string memory crackColor = data.isMutatedSeed ? "#86efac" : "#7dd3fc";
        string memory glowColor  = data.isMutatedSeed ? "#4ade80" : "#38bdf8";
        string memory outerGlow  = data.isMutatedSeed ? "#22c55e" : "#0ea5e9";
        string memory starsSVG   = _buildStars(data.tokenId);

        return string(abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 500 500">',
            '<defs>',
            '<radialGradient id="bg" cx="50%" cy="50%" r="50%">',
            '<stop offset="0%" stop-color="#050a08"/>',
            '<stop offset="100%" stop-color="#020508"/>',
            '</radialGradient>',
            '<radialGradient id="inner" cx="50%" cy="42%" r="50%">',
            '<stop offset="0%" stop-color="white"/>',
            '<stop offset="30%" stop-color="', glowColor, '">',
            '<animate attributeName="stop-color" values="', glowColor, ';white;', glowColor, '" dur="3s" repeatCount="indefinite"/>',
            '</stop>',
            '<stop offset="100%" stop-color="rgba(0,0,0,0)"/>',
            '</radialGradient>',
            '<radialGradient id="og" cx="50%" cy="50%" r="50%">',
            '<stop offset="0%" stop-color="', outerGlow, '" stop-opacity="0.18"/>',
            '<stop offset="100%" stop-color="rgba(0,0,0,0)"/>',
            '</radialGradient>',
            _seedStyles(data.isMutatedSeed, hueAnim, crackColor),
            '</defs>',
            '<rect width="500" height="500" fill="url(#bg)"/>',
            starsSVG,
            _seedBody(data.isMutatedSeed, crackColor),
            '</svg>'
        ));
    }

    function _seedStyles(bool isMutated, string memory hueAnim, string memory crackColor) internal pure returns (string memory) {
        string memory flickerStyle = isMutated
            ? ".fring{animation:fring 2.5s ease-in-out infinite;} @keyframes fring{0%,100%{opacity:0.08;}50%{opacity:0.3;}}"
            : ".fring{animation:fring 4s ease-in-out infinite;} @keyframes fring{0%,100%{opacity:0.05;}50%{opacity:0.18;}}";

        return string(abi.encodePacked(
            '<style>',
            '.crack{stroke:', crackColor, ';stroke-linecap:round;fill:none;}',
            '.shell{fill:none;stroke-width:1.2;}',
            flickerStyle,
            '</style>'
        ));
    }

    function _seedBody(bool isMutated, string memory crackColor) internal pure returns (string memory) {
        // Egg/seed shape - side view, pointed top, wide middle, tapered bottom
        // Centre: 250,250  Top: 250,142  Bottom: 250,368  WidestX: +/-72 at y~270
        string memory outerPath = "M250,142 C238,172 178,210 178,270 C178,310 210,360 250,368 C290,360 322,310 322,270 C322,210 262,172 250,142 Z";
        string memory flickerRing = isMutated
            ? '<ellipse cx="250" cy="255" rx="76" ry="118" fill="none" stroke="#86efac" stroke-width="2.5" stroke-dasharray="6 10" class="fring"/>'
            : '<ellipse cx="250" cy="255" rx="76" ry="118" fill="none" stroke="#7dd3fc" stroke-width="2" stroke-dasharray="5 9" class="fring"/>';

        return string(abi.encodePacked(
            // outer ambient glow
            '<ellipse cx="250" cy="255" rx="110" ry="145" fill="url(#og)">',
            '<animate attributeName="rx" values="105;118;105" dur="4s" repeatCount="indefinite"/>',
            '<animate attributeName="ry" values="140;155;140" dur="4s" repeatCount="indefinite"/>',
            '</ellipse>',

            // crystal shell fill
            '<path d="', outerPath, '" fill="#030d08" opacity="0.95"/>',

            // inner glow
            '<clipPath id="cp"><path d="', outerPath, '"/></clipPath>',
            '<ellipse cx="250" cy="230" rx="60" ry="80" fill="url(#inner)" clip-path="url(#cp)">',
            '<animate attributeName="ry" values="75;90;75" dur="3s" repeatCount="indefinite"/>',
            '<animate attributeName="opacity" values="0.85;1;0.85" dur="3s" repeatCount="indefinite"/>',
            '</ellipse>',

            // facet shading left
            '<path d="M250,142 C238,172 178,210 178,270 C178,310 210,360 250,368" fill="none" stroke="rgba(0,0,0,0.35)" stroke-width="28" clip-path="url(#cp)"/>',

            // vertical cracks - light bleeding through
            _seedCracks(crackColor),

            // outer shell border
            '<path d="', outerPath, '" class="shell" stroke="rgba(125,211,252,0.45)"/>',

            // top highlight - light catching crystal edge
            '<path d="M250,142 C241,168 190,208 182,262" fill="none" stroke="rgba(200,240,255,0.3)" stroke-width="1.5"/>',

            // mutated flicker ring
            flickerRing,

            // bright core centre
            '<circle cx="250" cy="222" r="10" fill="url(#inner)">',
            '<animate attributeName="r" values="8;13;8" dur="3s" repeatCount="indefinite"/>',
            '</circle>',
            '<circle cx="250" cy="222" r="4" fill="white" opacity="0.95"/>'
        ));
    }

    function _seedCracks(string memory crackColor) internal pure returns (string memory) {
        // 4 vertical cracks with individual pulse animations
        return string(abi.encodePacked(
            // crack 1
            '<path d="M208,178 L204,220 L210,262 L206,310 L208,348" class="crack" stroke-width="1.0" clip-path="url(#cp)">',
            '<animate attributeName="opacity" values="0.4;0.9;0.4" dur="3.2s" repeatCount="indefinite"/>',
            '</path>',
            '<path d="M208,220 L200,240 L208,260" fill="none" stroke="', crackColor, '" stroke-width="6" stroke-linecap="round" opacity="0.15" clip-path="url(#cp)">',
            '<animate attributeName="opacity" values="0.1;0.3;0.1" dur="3.2s" repeatCount="indefinite"/>',
            '</path>',

            // crack 2
            '<path d="M235,155 L231,200 L237,250 L233,300 L235,355" class="crack" stroke-width="1.1" clip-path="url(#cp)">',
            '<animate attributeName="opacity" values="0.5;1;0.5" dur="2.8s" repeatCount="indefinite"/>',
            '</path>',
            '<path d="M235,200 L225,228 L235,255" fill="none" stroke="', crackColor, '" stroke-width="8" stroke-linecap="round" opacity="0.18" clip-path="url(#cp)">',
            '<animate attributeName="opacity" values="0.12;0.35;0.12" dur="2.8s" repeatCount="indefinite"/>',
            '</path>',

            // crack 3
            '<path d="M265,155 L269,200 L263,252 L267,302 L265,355" class="crack" stroke-width="1.1" clip-path="url(#cp)">',
            '<animate attributeName="opacity" values="0.45;0.95;0.45" dur="3.5s" repeatCount="indefinite"/>',
            '</path>',
            '<path d="M265,200 L275,230 L265,258" fill="none" stroke="', crackColor, '" stroke-width="8" stroke-linecap="round" opacity="0.18" clip-path="url(#cp)">',
            '<animate attributeName="opacity" values="0.12;0.32;0.12" dur="3.5s" repeatCount="indefinite"/>',
            '</path>',

            // crack 4
            '<path d="M292,178 L296,222 L290,264 L294,312 L292,348" class="crack" stroke-width="1.0" clip-path="url(#cp)">',
            '<animate attributeName="opacity" values="0.4;0.88;0.4" dur="4.1s" repeatCount="indefinite"/>',
            '</path>',
            '<path d="M292,222 L302,244 L292,265" fill="none" stroke="', crackColor, '" stroke-width="6" stroke-linecap="round" opacity="0.15" clip-path="url(#cp)">',
            '<animate attributeName="opacity" values="0.1;0.28;0.1" dur="4.1s" repeatCount="indefinite"/>',
            '</path>'
        ));
    }

    // -------------------------------------------------------------------------
    // TOKEN URI BUILDERS
    // -------------------------------------------------------------------------
    function _buildTokenURI(TokenData memory data, string memory svg, uint256 dotsLeft) internal view returns (string memory) {
        string memory imageData = string(abi.encodePacked(
            "data:image/svg+xml;base64,",
            Base64.encode(bytes(svg))
        ));

        string memory coreType = data.isMutated ? "Mutated" : "Normal";
        string memory colorName = CORE_NAMES[data.colorIndex];
        uint256 daysPassed = (block.timestamp - data.mintedAt) / 1 days;

        string memory attributes = string(abi.encodePacked(
            '[',
            '{"trait_type":"Core Type","value":"', coreType, '"},',
            '{"trait_type":"Core Color","value":"', colorName, '"},',
            '{"trait_type":"Dots Remaining","value":', dotsLeft.toString(), '},',
            '{"trait_type":"Age (Days)","value":', daysPassed.toString(), '},',
            '{"trait_type":"Ready to Forge","value":"', dotsLeft == 0 ? "Yes" : "No", '"}',
            ']'
        ));

        string memory json = Base64.encode(bytes(string(abi.encodePacked(
            '{"name":"Galaxy Seeds #', data.tokenId.toString(), '",',
            '"description":"A living galaxy NFT. Each day one star falls into the core. When all 45 stars are consumed, burn 5 to forge a Seed.",',
            '"image":"', imageData, '",',
            '"attributes":', attributes,
            '}'
        ))));

        return string(abi.encodePacked("data:application/json;base64,", json));
    }

    function _buildSeedTokenURI(TokenData memory data, string memory svg) internal pure returns (string memory) {
        string memory imageData = string(abi.encodePacked(
            "data:image/svg+xml;base64,",
            Base64.encode(bytes(svg))
        ));

        string memory seedType = data.isMutatedSeed ? "Mutated Seed" : "Seed";
        string memory rarity   = data.isMutatedSeed ? "Mutated" : "Common";

        string memory attributes = string(abi.encodePacked(
            '[',
            '{"trait_type":"Token Type","value":"', seedType, '"},',
            '{"trait_type":"Seed Rarity","value":"', rarity, '"},',
            '{"trait_type":"PFP Ready","value":"Soon"}',
            ']'
        ));

        string memory json = Base64.encode(bytes(string(abi.encodePacked(
            '{"name":"Galaxy Seeds - Seed #', data.tokenId.toString(), '",',
            '"description":"A crystal seed forged from consumed galaxy cores. Its light grows from within. The PFP awaits.",',
            '"image":"', imageData, '",',
            '"attributes":', attributes,
            '}'
        ))));

        return string(abi.encodePacked("data:application/json;base64,", json));
    }
}
