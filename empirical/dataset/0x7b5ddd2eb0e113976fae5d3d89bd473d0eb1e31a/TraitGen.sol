// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title  TraitGen
 * @notice Derives deterministic traits from tokenId.
 *         Same tokenId = same traits. Forever.
 */
library TraitGen {

    struct Traits {
        uint8 background;   // 0-3
        uint8 language;     // 0-4
        uint8 status;       // 0-4
        uint8 errorType;    // 0-4
        uint8 textColor;    // 0-4
        uint8 cursorStyle;  // 0-2
        uint8 lineCount;    // 6-12 (terminal lines shown)
    }

    // ── Labels (for metadata) ──────────────────────────

    function backgroundName(uint8 i) internal pure returns (string memory) {
        if (i == 0) return "Void";
        if (i == 1) return "Matrix";
        if (i == 2) return "Static";
        return "Dark";
    }

    function languageName(uint8 i) internal pure returns (string memory) {
        if (i == 0) return "Solidity";
        if (i == 1) return "Assembly";
        if (i == 2) return "Python";
        if (i == 3) return "Rust";
        return "Bytecode";
    }

    function statusName(uint8 i) internal pure returns (string memory) {
        if (i == 0) return "root";
        if (i == 1) return "ghost";
        if (i == 2) return "traced";
        if (i == 3) return "null";
        return "overflow";
    }

    function errorName(uint8 i) internal pure returns (string memory) {
        if (i == 0) return "404";
        if (i == 1) return "segfault";
        if (i == 2) return "kernel panic";
        if (i == 3) return "timeout";
        return "null pointer";
    }

    function colorHex(uint8 i) internal pure returns (string memory) {
        if (i == 0) return "#00ff41"; // green
        if (i == 1) return "#ff3131"; // red
        if (i == 2) return "#ffb347"; // amber
        if (i == 3) return "#ffffff"; // white
        return "#00e5ff";             // cyan
    }

    function bgHex(uint8 i) internal pure returns (string memory) {
        if (i == 0) return "#000000"; // void
        if (i == 1) return "#001100"; // matrix
        if (i == 2) return "#0a0a0a"; // static
        return "#0d0d0d";             // dark
    }

    // ── Derive traits ──────────────────────────────────

    function generate(uint256 tokenId) internal pure returns (Traits memory t) {
        // Each seed uses a different salt so traits don't correlate
        bytes32 seed = keccak256(abi.encodePacked(tokenId));

        t.background  = uint8(uint256(keccak256(abi.encodePacked(seed, "bg")))   % 4);
        t.language    = uint8(uint256(keccak256(abi.encodePacked(seed, "lang"))) % 5);
        t.status      = uint8(uint256(keccak256(abi.encodePacked(seed, "stat"))) % 5);
        t.errorType   = uint8(uint256(keccak256(abi.encodePacked(seed, "err")))  % 5);
        t.textColor   = uint8(uint256(keccak256(abi.encodePacked(seed, "col")))  % 5);
        t.cursorStyle = uint8(uint256(keccak256(abi.encodePacked(seed, "cur")))  % 3);
        t.lineCount   = uint8(uint256(keccak256(abi.encodePacked(seed, "lns")))  % 7) + 6;
    }
}
