// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

library HeraldiaTraits {
    
    struct TokenTraits {
        // sHash
        uint16 emblemTSize;     // 10, 20, 40, 80
        uint8 emblemTMirror;    // 0=X4, 1=X2, 2=X4_SPLIT
        uint8 emblemPSize;      // 10 или 20 — для Layer3 grid

        // dHash
        bool isDarkTheme;
        uint8 patternStyle;
        uint8 bgTType;
        uint16 bgTSize;
        uint8 bgTDivide;

        uint8 bgIndex;
        uint8 sizeIndex;
        uint8 patternIndex;
        uint8 styleIndex;

        uint8 edgeTouchIndex;   // 0-6
    }

    function resolveTraits(bytes32 sHash, bytes32 dHash, uint8 edgeTouchIndex) internal pure returns (TokenTraits memory t) {
        // Emblem size: sHash[0] % 4
        t.sizeIndex = uint8(sHash[0]) % 4;
        if (t.sizeIndex == 0) { t.emblemTSize = 10; t.emblemPSize = 20; }
        else if (t.sizeIndex == 1) { t.emblemTSize = 20; t.emblemPSize = 20; }
        else if (t.sizeIndex == 2) { t.emblemTSize = 40; t.emblemPSize = 10; }
        else { t.emblemTSize = 80; t.emblemPSize = 10; }

        // Emblem mirror: sHash[1] % 3
        t.emblemTMirror = uint8(sHash[1]) % 3;
        t.styleIndex = t.emblemTMirror;

        // Theme: dHash[0] % 2
        t.isDarkTheme = (uint8(dHash[0]) % 2) == 0;

        // Pattern: dHash[1] % 4
        t.patternIndex = uint8(dHash[1]) % 4;
        t.patternStyle = t.patternIndex + 1;

        // Background: dHash[2] % 21
        t.bgIndex = uint8(dHash[2]) % 21;
        (t.bgTType, t.bgTSize, t.bgTDivide) = _bgParams(t.bgIndex);

        // Edge Touch
        t.edgeTouchIndex = edgeTouchIndex;
    }

    function getTransferGroup(uint256 transfers) internal pure returns (string memory) {
        if (transfers == 0)           return "0";
        if (transfers <= 2)           return "1-2";
        if (transfers <= 4)           return "3-4";
        if (transfers <= 8)           return "5-8";
        if (transfers <= 16)          return "9-16";
        if (transfers <= 32)          return "17-32";
        if (transfers <= 64)          return "33-64";
        if (transfers <= 128)         return "65-128";
        if (transfers <= 256)         return "129-256";
        if (transfers <= 512)         return "257-512";
        if (transfers <= 1024)        return "513-1024";
        if (transfers <= 2048)        return "1025-2048";
        if (transfers <= 4096)        return "2049-4096";
        return "4097+";
    }

    // ── Emblem = size + Edge Touch ─────────────────────────────
    function getEmblemName(uint8 sizeIdx, uint8 edgeTouchIdx) internal pure returns (string memory) {
        string memory size = getSizeName(sizeIdx);
        string memory edge = getEdgeTouchName(edgeTouchIdx);
        return string(abi.encodePacked(size, " ", edge));
    }

    function getEdgeTouchName(uint8 idx) internal pure returns (string memory) {
        if (idx == 0) return "Floating";
        if (idx == 1) return "One Edge";
        if (idx == 2) return "Two Edges Corner";
        if (idx == 3) return "Two Edges Wide";
        if (idx == 4) return "Two Edges Tall";
        if (idx == 5) return "Three Edges";
        return "Four Edges";
    }

    function _bgParams(uint8 idx) private pure returns (uint8 t, uint16 s, uint8 d) {
        if (idx == 0) return (1, 1, 1);
        if (idx == 1) return (2, 10, 2);
        if (idx == 2) return (2, 20, 4);
        if (idx == 3) return (2, 40, 6);
        if (idx == 4) return (2, 80, 8);
        if (idx == 5) return (3, 10, 2);
        if (idx == 6) return (3, 20, 4);
        if (idx == 7) return (3, 40, 6);
        if (idx == 8) return (3, 80, 8);
        if (idx == 9) return (4, 10, 2);
        if (idx == 10) return (4, 20, 4);
        if (idx == 11) return (4, 40, 6);
        if (idx == 12) return (4, 80, 8);
        if (idx == 13) return (5, 10, 2);
        if (idx == 14) return (5, 20, 4);
        if (idx == 15) return (5, 40, 6);
        if (idx == 16) return (5, 80, 8);
        if (idx == 17) return (6, 10, 2);
        if (idx == 18) return (6, 20, 4);
        if (idx == 19) return (6, 40, 6);
        return (6, 80, 8);
    }

    function getBackgroundName(uint8 idx) internal pure returns (string memory) {
        if (idx == 0) return "Solid";
        if (idx == 1) return "Flat Bold";
        if (idx == 2) return "Flat Medium";
        if (idx == 3) return "Flat Regular";
        if (idx == 4) return "Flat Light";
        if (idx == 5) return "Upright Bold";
        if (idx == 6) return "Upright Medium";
        if (idx == 7) return "Upright Regular";
        if (idx == 8) return "Upright Light";
        if (idx == 9) return "Slant Bold";
        if (idx == 10) return "Slant Medium";
        if (idx == 11) return "Slant Regular";
        if (idx == 12) return "Slant Light";
        if (idx == 13) return "Grid Bold";
        if (idx == 14) return "Grid Medium";
        if (idx == 15) return "Grid Regular";
        if (idx == 16) return "Grid Light";
        if (idx == 17) return "Dot Bold";
        if (idx == 18) return "Dot Medium";
        if (idx == 19) return "Dot Regular";
        return "Dot Light";
    }

    function getSizeName(uint8 idx) internal pure returns (string memory) {
        if (idx == 0) return "Primitive";
        if (idx == 1) return "Simple";
        if (idx == 2) return "Detailed";
        return "Complex";
    }

    function getPatternName(uint8 idx) internal pure returns (string memory) {
        if (idx == 0) return "Pixel";
        if (idx == 1) return "Dot";
        if (idx == 2) return "Cross";
        return "Mix";
    }

    function getStyleName(uint8 idx) internal pure returns (string memory) {
        if (idx == 0) return "Classic";
        if (idx == 1) return "Dual";
        return "Dynamic";
    }

    function getThemeName(bool dark) internal pure returns (string memory) {
        return dark ? "Sun" : "Moon";
    }
}
