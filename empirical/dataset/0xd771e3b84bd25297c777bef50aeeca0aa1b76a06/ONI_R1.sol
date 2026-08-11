// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

/// @title ONI Renderer 1 — Background + Aura
contract ONIRenderer1 {

    string internal constant Q = '"';
    string internal constant V = "'";

    function bgName(uint256 id) public pure returns (string memory) {
        uint256 t = (id * 7919 + 42) % 8;
        if (t == 0) return "Night";
        if (t == 1) return "Flames";
        if (t == 2) return "Blossom";
        if (t == 3) return "Temple";
        if (t == 4) return "Thunder";
        if (t == 5) return "Void";
        if (t == 6) return "Blood Moon";
        return "Fog";
    }

    function auraName(uint256 id) public pure returns (string memory) {
        uint256 t = _rng(id, 11) % 6;
        if (t == 0) return "None";
        if (t == 1) return "Fire";
        if (t == 2) return "Lightning";
        if (t == 3) return "Dark";
        if (t == 4) return "Holy";
        return "Poison";
    }

    function _rng(uint256 seed, uint256 offset) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(seed * 7919 + 42 + offset)));
    }

    function _bgColors(uint256 t) internal pure returns (string memory c1, string memory c2) {
        if (t == 0) return ("#050510", "#0a0a20");
        if (t == 1) return ("#1a0500", "#2a0800");
        if (t == 2) return ("#1a0510", "#200810");
        if (t == 3) return ("#080510", "#100a18");
        if (t == 4) return ("#050510", "#080815");
        if (t == 5) return ("#000000", "#050505");
        if (t == 6) return ("#150005", "#220008");
        return ("#0a0a12", "#121218");
    }

    function _auraColor(uint256 t) internal pure returns (string memory) {
        if (t == 1) return "#FF4400";
        if (t == 2) return "#FFDD00";
        if (t == 3) return "#440044";
        if (t == 4) return "#FFFF88";
        if (t == 5) return "#00FF44";
        return "transparent";
    }

    function renderBg(uint256 id) public pure returns (string memory) {
        uint256 bgt = (id * 7919 + 42) % 8;
        uint256 at = _rng(id, 11) % 6;
        (string memory c1, string memory c2) = _bgColors(bgt);
        string memory auraC = _auraColor(at);

        string memory base = string(abi.encodePacked(
            '<defs>',
            '<linearGradient id="bg" x1="0%" y1="0%" x2="0%" y2="100%">',
            '<stop offset="0%" style="stop-color:', c1, '"/>',
            '<stop offset="100%" style="stop-color:', c2, '"/>',
            '</linearGradient>',
            '<radialGradient id="aura" cx="50%" cy="45%" r="60%">',
            '<stop offset="0%" style="stop-color:', auraC, ';stop-opacity:0.25"/>',
            '<stop offset="100%" style="stop-color:', auraC, ';stop-opacity:0"/>',
            '</radialGradient>',
            '<radialGradient id="shadow" cx="50%" cy="50%" r="50%">',
            '<stop offset="0%" style="stop-color:#000;stop-opacity:0.5"/>',
            '<stop offset="100%" style="stop-color:#000;stop-opacity:0"/>',
            '</radialGradient>',
            '</defs>',
            '<rect width="300" height="380" fill="url(#bg)"/>'
        ));

        string memory extras = "";
        if (bgt == 6) {
            extras = string(abi.encodePacked(
                '<circle cx="220" cy="70" r="50" fill="#CC0020" fill-opacity="0.12"/>',
                '<circle cx="220" cy="70" r="38" fill="#CC0020" fill-opacity="0.1"/>',
                '<circle cx="220" cy="70" r="25" fill="#CC0020" fill-opacity="0.15"/>'
            ));
        } else if (bgt == 1) {
            extras = string(abi.encodePacked(
                '<polygon points="30,330 40,270 50,330" fill="#FF4400" fill-opacity="0.12"/>',
                '<polygon points="76,330 86,270 96,330" fill="#FF4400" fill-opacity="0.12"/>',
                '<polygon points="122,330 132,270 142,330" fill="#FF4400" fill-opacity="0.12"/>',
                '<polygon points="168,330 178,270 188,330" fill="#FF4400" fill-opacity="0.12"/>',
                '<polygon points="214,330 224,270 234,330" fill="#FF4400" fill-opacity="0.12"/>'
            ));
        } else if (bgt == 4) {
            extras = string(abi.encodePacked(
                '<line x1="60" y1="0" x2="40" y2="120" stroke="#FFDD00" stroke-width="1" stroke-opacity="0.1"/>',
                '<line x1="150" y1="0" x2="130" y2="120" stroke="#FFDD00" stroke-width="1" stroke-opacity="0.1"/>',
                '<line x1="240" y1="0" x2="220" y2="120" stroke="#FFDD00" stroke-width="1" stroke-opacity="0.1"/>'
            ));
        }

        string memory auraLayer = at > 0 ? '<rect width="300" height="380" fill="url(#aura)"/>' : "";

        return string(abi.encodePacked(base, extras, auraLayer));
    }

    function renderAura(uint256 id) public pure returns (string memory) {
        uint256 at = _rng(id, 11) % 6;
        if (at == 0) return "";
        string memory ac = _auraColor(at);
        string memory particles = "";
        uint256 seed = id * 1337;
        for (uint256 i = 0; i < 10; i++) {
            uint256 px = 80 + (seed * (i + 1) * 3) % 140;
            uint256 py = 100 + (seed * (i + 2) * 7) % 150;
            uint256 pr = 1 + (seed * (i + 3)) % 3;
            particles = string(abi.encodePacked(
                particles,
                '<circle cx="', _n(px), '" cy="', _n(py), '" r="', _n(pr),
                '" fill="', ac, '" fill-opacity="0.4"/>'
            ));
        }
        return particles;
    }

    function renderShadow() public pure returns (string memory) {
        return '<ellipse cx="150" cy="298" rx="68" ry="12" fill="url(#shadow)"/>';
    }

    function _n(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        uint256 tmp = v; uint256 len;
        while (tmp != 0) { len++; tmp /= 10; }
        bytes memory buf = new bytes(len);
        while (v != 0) { buf[--len] = bytes1(uint8(48 + v % 10)); v /= 10; }
        return string(buf);
    }
}
