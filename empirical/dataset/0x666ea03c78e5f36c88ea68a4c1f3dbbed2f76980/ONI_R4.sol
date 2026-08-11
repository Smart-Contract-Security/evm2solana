// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

/// @title ONI Renderer 4 — Neck + Frame + tokenURI assembly
contract ONIRenderer4 {

    function _rng(uint256 seed, uint256 offset) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(seed * 7919 + 42 + offset)));
    }

    function _n(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        uint256 tmp = v; uint256 len;
        while (tmp != 0) { len++; tmp /= 10; }
        bytes memory buf = new bytes(len);
        while (v != 0) { buf[--len] = bytes1(uint8(48 + v % 10)); v /= 10; }
        return string(buf);
    }

    function skinName(uint256 id) public pure returns (string memory) {
        uint256 t = _rng(id, 1) % 8;
        if (t == 0) return "Crimson";
        if (t == 1) return "Cobalt";
        if (t == 2) return "Jade";
        if (t == 3) return "Violet";
        if (t == 4) return "Gold";
        if (t == 5) return "Ash";
        if (t == 6) return "Void";
        return "Teal";
    }

    function rarityName(uint256 id) public pure returns (string memory) {
        uint256 roll = _rng(id, 99) % 100;
        if (roll >= 98) return "Mythical";
        if (roll >= 96) return "Fallen";
        if (roll >= 94) return "Ancient";
        if (roll >= 88) return "Rare";
        if (roll >= 65) return "Uncommon";
        return "Common";
    }

    function _rarityColor(uint256 id) internal pure returns (string memory) {
        uint256 roll = _rng(id, 99) % 100;
        if (roll >= 98) return "#FFD700";
        if (roll >= 96) return "#9944FF";
        if (roll >= 94) return "#00FF88";
        if (roll >= 88) return "#4169E1";
        if (roll >= 65) return "#888888";
        return "#444444";
    }

    function _skinBase(uint256 id) internal pure returns (string memory) {
        uint256 t = _rng(id, 1) % 8;
        if (t == 0) return "#CC2200";
        if (t == 1) return "#1a44CC";
        if (t == 2) return "#228844";
        if (t == 3) return "#882288";
        if (t == 4) return "#CC8800";
        if (t == 5) return "#AAAAAA";
        if (t == 6) return "#222222";
        return "#118888";
    }

    function _skinMid(uint256 id) internal pure returns (string memory) {
        uint256 t = _rng(id, 1) % 8;
        if (t == 0) return "#AA1800";
        if (t == 1) return "#1230AA";
        if (t == 2) return "#186630";
        if (t == 3) return "#661666";
        if (t == 4) return "#AA6600";
        if (t == 5) return "#888888";
        if (t == 6) return "#111111";
        return "#006666";
    }

    function renderNeck(uint256 id) public pure returns (string memory) {
        string memory sb = _skinBase(id);
        string memory sm = _skinMid(id);
        bool hasNecklace = _rng(id, 14) % 2 == 0;
        string memory necklace = "";
        if (hasNecklace) {
            string memory ec = _eyeColor(id);
            necklace = string(abi.encodePacked(
                '<path d="M132,160 Q150,152 168,160" fill="none" stroke="#FFD700" stroke-width="1.5"/>',
                '<circle cx="150" cy="152" r="4" fill="', ec, '"/>',
                '<circle cx="149" cy="151" r="2" fill="rgba(255,255,255,0.5)"/>'
            ));
        }
        return string(abi.encodePacked(
            '<polygon points="136,162 164,162 158,142 142,142" fill="', sb, '" stroke="rgba(0,0,0,0.18)" stroke-width="0.6"/>',
            '<polygon points="136,162 142,142 150,148" fill="', sm, '" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            necklace
        ));
    }

    function _eyeColor(uint256 id) internal pure returns (string memory) {
        uint256 t = _rng(id, 3) % 8;
        if (t == 0) return "#FF4400";
        if (t == 1) return "#8800FF";
        if (t == 2) return "#0088FF";
        if (t == 3) return "#00FF44";
        if (t == 4) return "#FF0088";
        if (t == 5) return "#FFDD00";
        if (t == 6) return "#00FFFF";
        return "#FF4488";
    }

    function renderFrame(uint256 id) public pure returns (string memory) {
        string memory rc = _rarityColor(id);
        string memory rn = rarityName(id);
        string memory sn = skinName(id);
        string memory idStr = _n(id);
        return string(abi.encodePacked(
            '<rect x="4" y="4" width="292" height="372" fill="none" stroke="', rc, '" stroke-width="1.5"/>',
            '<rect x="8" y="8" width="284" height="364" fill="none" stroke="', rc, '" stroke-width="0.5" stroke-opacity="0.4"/>',
            '<line x1="3" y1="4" x2="17" y2="4" stroke="', rc, '" stroke-width="1.5"/>',
            '<line x1="4" y1="3" x2="4" y2="17" stroke="', rc, '" stroke-width="1.5"/>',
            '<line x1="283" y1="4" x2="297" y2="4" stroke="', rc, '" stroke-width="1.5"/>',
            '<line x1="296" y1="3" x2="296" y2="17" stroke="', rc, '" stroke-width="1.5"/>',
            '<line x1="3" y1="376" x2="17" y2="376" stroke="', rc, '" stroke-width="1.5"/>',
            '<line x1="4" y1="363" x2="4" y2="377" stroke="', rc, '" stroke-width="1.5"/>',
            '<line x1="283" y1="376" x2="297" y2="376" stroke="', rc, '" stroke-width="1.5"/>',
            '<line x1="296" y1="363" x2="296" y2="377" stroke="', rc, '" stroke-width="1.5"/>',
            '<rect x="4" y="4" width="292" height="26" fill="rgba(0,0,0,0.85)"/>',
            '<text x="14" y="22" fill="', rc, '" font-size="13" font-family="Bebas Neue,sans-serif">&#9961; ONI</text>',
            '<text x="288" y="20" fill="rgba(255,255,255,0.4)" font-size="8" font-family="monospace" text-anchor="end">#', idStr, '</text>',
            '<rect x="4" y="352" width="292" height="24" fill="rgba(0,0,0,0.85)"/>',
            '<text x="14" y="366" fill="', rc, '" font-size="7.5" font-family="monospace">', sn, '</text>',
            '<rect x="192" y="352" width="98" height="24" fill="', rc, '" fill-opacity="0.2"/>',
            '<text x="241" y="367" fill="', rc, '" font-size="8.5" font-family="Bebas Neue,sans-serif" text-anchor="middle">', rn, '</text>'
        ));
    }

    function renderRare(uint256 id) public pure returns (string memory) {
        uint256 roll = _rng(id, 99) % 100;
        if (roll >= 98) return string(abi.encodePacked(
            '<rect width="300" height="380" fill="#FFCC00" fill-opacity="0.06"/>',
            '<ellipse cx="150" cy="42" rx="32" ry="8" fill="none" stroke="#FFD700" stroke-width="3" stroke-opacity="0.6"/>',
            '<line x1="150" y1="30" x2="205" y2="70" stroke="#FFD700" stroke-width="1" stroke-opacity="0.2"/>',
            '<line x1="150" y1="30" x2="95" y2="70" stroke="#FFD700" stroke-width="1" stroke-opacity="0.2"/>',
            '<line x1="150" y1="30" x2="150" y2="88" stroke="#FFD700" stroke-width="1" stroke-opacity="0.2"/>'
        ));
        if (roll >= 96) return string(abi.encodePacked(
            '<ellipse cx="150" cy="32" rx="24" ry="6" fill="none" stroke="rgba(255,255,200,0.35)" stroke-width="2.5" stroke-dasharray="4,3"/>',
            '<path d="M104,75 Q35,45 58,118 Q75,92 98,98 Z" fill="rgba(20,0,40,0.55)"/>',
            '<path d="M196,75 Q265,45 242,118 Q225,92 202,98 Z" fill="rgba(20,0,40,0.55)"/>'
        ));
        if (roll >= 94) return string(abi.encodePacked(
            '<rect width="300" height="380" fill="#00CC66" fill-opacity="0.04"/>',
            '<circle cx="120" cy="100" r="3" fill="#00FF88" fill-opacity="0.4"/>',
            '<circle cx="180" cy="80" r="2" fill="#00FF88" fill-opacity="0.5"/>',
            '<circle cx="90" cy="150" r="2" fill="#00FF88" fill-opacity="0.35"/>',
            '<circle cx="210" cy="130" r="3" fill="#00FF88" fill-opacity="0.4"/>',
            '<circle cx="150" cy="60" r="2" fill="#00FF88" fill-opacity="0.45"/>'
        ));
        return "";
    }

    function buildAttributes(
        uint256 id,
        string memory skinN,
        string memory headN,
        string memory hornN,
        string memory hairN,
        string memory eyeN,
        string memory mouthN,
        string memory outfitN,
        string memory weaponN,
        string memory rarityN,
        string memory bgN,
        string memory auraN
    ) public pure returns (string memory) {
        return string(abi.encodePacked(
            '[{"trait_type":"Skin","value":"', skinN,
            '"},{"trait_type":"Head","value":"', headN,
            '"},{"trait_type":"Horns","value":"', hornN,
            '"},{"trait_type":"Hair","value":"', hairN,
            '"},{"trait_type":"Eyes","value":"', eyeN,
            '"},{"trait_type":"Mouth","value":"', mouthN,
            '"},{"trait_type":"Outfit","value":"', outfitN,
            '"},{"trait_type":"Weapon","value":"', weaponN,
            '"},{"trait_type":"Background","value":"', bgN,
            '"},{"trait_type":"Aura","value":"', auraN,
            '"},{"trait_type":"Rarity","value":"', rarityN,
            '"}]'
        ));
    }

    function buildSVGTop(
        string memory bg, string memory aura, string memory shadow,
        string memory legs, string memory body, string memory arms,
        string memory weapon, string memory neck, string memory head
    ) public pure returns (string memory) {
        return string(abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 300 380" width="300" height="380" shape-rendering="geometricPrecision">',
            bg, aura, shadow, legs, body, arms, weapon, neck, head
        ));
    }

    function buildSVGBot(
        string memory horns, string memory hair, string memory eyes,
        string memory nose, string memory mouth, string memory faceTat,
        string memory rare, string memory frame
    ) public pure returns (string memory) {
        return string(abi.encodePacked(
            horns, hair, eyes, nose, mouth, faceTat, rare, frame,
            '</svg>'
        ));
    }
}
