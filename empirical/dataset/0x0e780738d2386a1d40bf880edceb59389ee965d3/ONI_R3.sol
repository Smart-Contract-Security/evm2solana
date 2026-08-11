// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

/// @title ONI Renderer 3 — Head + Horns + Hair + Eyes + Mouth + Face Tattoo
contract ONIRenderer3 {

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

    function headName(uint256 id) public pure returns (string memory) {
        uint256 t = _rng(id, 2) % 8;
        if (t == 0) return "Oni";
        if (t == 1) return "Hannya";
        if (t == 2) return "Tengu";
        if (t == 3) return "Kitsune";
        if (t == 4) return "Dragon";
        if (t == 5) return "Skull";
        if (t == 6) return "Cyber";
        return "Angel";
    }

    function hornName(uint256 id) public pure returns (string memory) {
        uint256 t = _rng(id, 4) % 7;
        if (t == 0) return "None";
        if (t == 1) return "Single";
        if (t == 2) return "Twin Short";
        if (t == 3) return "Twin Long";
        if (t == 4) return "Curved";
        if (t == 5) return "Crown";
        return "Broken";
    }

    function hairName(uint256 id) public pure returns (string memory) {
        uint256 t = _rng(id, 7) % 7;
        if (t == 0) return "None";
        if (t == 1) return "Wild";
        if (t == 2) return "Mohawk";
        if (t == 3) return "Top Knot";
        if (t == 4) return "Spiky";
        if (t == 5) return "Flowing";
        return "Braided";
    }

    function eyeName(uint256 id) public pure returns (string memory) {
        uint256 t = _rng(id, 5) % 8;
        if (t == 0) return "Normal";
        if (t == 1) return "Spiral";
        if (t == 2) return "Flame";
        if (t == 3) return "Diamond";
        if (t == 4) return "Star";
        if (t == 5) return "Bloodshot";
        if (t == 6) return "Pupilless";
        return "Glowing";
    }

    function mouthName(uint256 id) public pure returns (string memory) {
        uint256 t = _rng(id, 8) % 6;
        if (t == 0) return "Fangs";
        if (t == 1) return "Tusks";
        if (t == 2) return "Stitched";
        if (t == 3) return "Roar";
        if (t == 4) return "Smirk";
        return "Hidden";
    }

    function faceTatName(uint256 id) public pure returns (string memory) {
        uint256 t = _rng(id, 10) % 6;
        if (t == 0) return "None";
        if (t == 1) return "Tribal";
        if (t == 2) return "Kanji";
        if (t == 3) return "Flame";
        if (t == 4) return "Geometric";
        return "Rune";
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

    function _skinDark(uint256 id) internal pure returns (string memory) {
        uint256 t = _rng(id, 1) % 8;
        if (t == 0) return "#880000";
        if (t == 1) return "#0a2088";
        if (t == 2) return "#0e4420";
        if (t == 3) return "#440044";
        if (t == 4) return "#884400";
        if (t == 5) return "#666666";
        if (t == 6) return "#080808";
        return "#004444";
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

    function _hornColor(uint256 id) internal pure returns (string memory) {
        uint256 t = _rng(id, 12) % 7;
        if (t == 0) return "#FFD700";
        if (t == 1) return "#C0C0C0";
        if (t == 2) return "#FF4400";
        if (t == 3) return "#8800FF";
        if (t == 4) return "#00CCFF";
        if (t == 5) return "#FF0044";
        return "#CCCCCC";
    }

    function _hairColor(uint256 id) internal pure returns (string memory) {
        uint256 t = _rng(id, 13) % 7;
        if (t == 0) return "#111111";
        if (t == 1) return "#8B0000";
        if (t == 2) return "#FFD700";
        if (t == 3) return "#000088";
        if (t == 4) return "#FF0088";
        if (t == 5) return "#00AA44";
        return "#777777";
    }

    function renderHead(uint256 id) public pure returns (string memory) {
        uint256 ht = _rng(id, 2) % 8;
        string memory sb = _skinBase(id);
        string memory sm = _skinMid(id);
        string memory sd = _skinDark(id);
        string memory ec = _eyeColor(id);

        if (ht == 0 || ht == 7) return _headOni(sb, sm, sd, ht == 7);
        if (ht == 1) return _headHannya(sb, sm, sd);
        if (ht == 2) return _headTengu(sb, sm, sd);
        if (ht == 3) return _headKitsune(sb, sm, sd);
        if (ht == 4) return _headDragon(sb, sm, sd);
        if (ht == 5) return _headSkull(sb, sm, sd);
        return _headCyber(sb, sm, sd, ec);
    }

    function _headOni(string memory sb, string memory sm, string memory sd, bool isAngel) internal pure returns (string memory) {
        string memory halo = isAngel ? string(abi.encodePacked(
            '<ellipse cx="150" cy="42" rx="28" ry="7" fill="none" stroke="#FFD700" stroke-width="2.5" stroke-opacity="0.7"/>',
            '<ellipse cx="150" cy="42" rx="28" ry="7" fill="none" stroke="rgba(255,255,200,0.3)" stroke-width="5"/>'
        )) : "";
        return string(abi.encodePacked(
            halo,
            '<polygon points="100,102 200,102 195,172 105,172" fill="', sb, '" stroke="rgba(0,0,0,0.18)" stroke-width="0.6"/>',
            '<polygon points="100,102 110,152 150,170 105,172" fill="', sm, '" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<polygon points="200,102 190,152 150,170 195,172" fill="', sd, '" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<polygon points="100,102 150,170 200,102" fill="rgba(0,0,0,0.06)" stroke="none"/>',
            '<polygon points="100,108 88,88 102,132" fill="', sm, '" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<polygon points="200,108 212,88 198,132" fill="', sd, '" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<polygon points="100,110 122,95 140,110" fill="rgba(255,255,255,0.1)" stroke="none"/>',
            '<polygon points="200,110 178,95 160,110" fill="rgba(255,255,255,0.1)" stroke="none"/>'
        ));
    }

    function _headHannya(string memory sb, string memory sm, string memory sd) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<polygon points="105,95 195,95 190,178 110,178" fill="', sb, '" stroke="rgba(0,0,0,0.18)" stroke-width="0.6"/>',
            '<polygon points="105,95 115,160 150,175 110,178" fill="', sm, '" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<polygon points="195,95 185,160 150,175 190,178" fill="', sd, '" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<polygon points="130,165 170,165 150,188" fill="', sm, '" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<polygon points="105,102 93,82 107,128" fill="', sm, '" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<polygon points="195,102 207,82 193,128" fill="', sd, '" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>'
        ));
    }

    function _headTengu(string memory sb, string memory sm, string memory sd) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<polygon points="102,106 198,106 193,168 107,168" fill="', sb, '" stroke="rgba(0,0,0,0.18)" stroke-width="0.6"/>',
            '<polygon points="102,106 112,155 150,164 107,168" fill="', sm, '" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<polygon points="198,106 188,155 150,164 193,168" fill="', sd, '" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<polygon points="144,122 156,122 150,158" fill="rgba(0,0,0,0.2)" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<polygon points="144,122 150,158 146,150" fill="rgba(0,0,0,0.3)" stroke="none"/>',
            '<polygon points="102,112 90,92 106,136" fill="', sm, '" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<polygon points="198,112 210,92 194,136" fill="', sd, '" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>'
        ));
    }

    function _headKitsune(string memory sb, string memory sm, string memory sd) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<polygon points="106,108 194,108 189,166 111,166" fill="', sb, '" stroke="rgba(0,0,0,0.18)" stroke-width="0.6"/>',
            '<polygon points="106,108 116,152 150,162 111,166" fill="', sm, '" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<polygon points="194,108 184,152 150,162 189,166" fill="', sd, '" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<polygon points="106,108 90,68 124,88" fill="', sb, '" stroke="rgba(0,0,0,0.18)" stroke-width="0.6"/>',
            '<polygon points="194,108 210,68 176,88" fill="', sb, '" stroke="rgba(0,0,0,0.18)" stroke-width="0.6"/>',
            '<polygon points="104,100 92,72 120,86" fill="rgba(255,255,255,0.2)" stroke="none"/>',
            '<polygon points="196,100 208,72 180,86" fill="rgba(255,255,255,0.2)" stroke="none"/>'
        ));
    }

    function _headDragon(string memory sb, string memory sm, string memory sd) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<polygon points="98,100 202,100 196,172 104,172" fill="', sb, '" stroke="rgba(0,0,0,0.18)" stroke-width="0.6"/>',
            '<polygon points="98,100 108,156 150,168 104,172" fill="', sm, '" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<polygon points="202,100 192,156 150,168 196,172" fill="', sd, '" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<polygon points="98,102 125,88 140,102" fill="rgba(0,0,0,0.22)" stroke="none"/>',
            '<polygon points="202,102 175,88 160,102" fill="rgba(0,0,0,0.22)" stroke="none"/>',
            '<polygon points="98,112 86,92 104,136" fill="', sm, '" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<polygon points="202,112 214,92 196,136" fill="', sd, '" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>'
        ));
    }

    function _headSkull(string memory sb, string memory sm, string memory sd) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<polygon points="102,106 198,106 192,168 108,168" fill="', sb, '" stroke="rgba(0,0,0,0.18)" stroke-width="0.6"/>',
            '<polygon points="102,106 112,154 150,165 108,168" fill="', sm, '" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<polygon points="198,106 188,154 150,165 192,168" fill="', sd, '" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<path d="M142,74 L146,114 L160,124" fill="none" stroke="rgba(0,0,0,0.42)" stroke-width="1.2"/>',
            '<path d="M168,82 L172,102" fill="none" stroke="rgba(0,0,0,0.35)" stroke-width="1"/>',
            '<polygon points="102,116 90,96 106,140" fill="', sm, '" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<polygon points="198,116 210,96 194,140" fill="', sd, '" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>'
        ));
    }

    function _headCyber(string memory sb, string memory sm, string memory sd, string memory ec) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<polygon points="100,104 200,104 194,170 106,170" fill="', sb, '" stroke="rgba(0,0,0,0.18)" stroke-width="0.6"/>',
            '<polygon points="100,104 110,152 150,166 106,170" fill="', sm, '" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<polygon points="200,104 190,152 150,166 194,170" fill="', sd, '" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<rect x="114" y="110" width="24" height="20" fill="none" stroke="', ec, '" stroke-width="0.8" stroke-opacity="0.7"/>',
            '<rect x="162" y="110" width="24" height="20" fill="none" stroke="', ec, '" stroke-width="0.8" stroke-opacity="0.7"/>',
            '<circle cx="119" cy="120" r="1.5" fill="', ec, '" fill-opacity="0.8"/>',
            '<circle cx="125" cy="120" r="1.5" fill="', ec, '" fill-opacity="0.8"/>',
            '<circle cx="131" cy="120" r="1.5" fill="', ec, '" fill-opacity="0.8"/>',
            '<polygon points="100,114 88,94 106,138" fill="', sm, '" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<polygon points="200,114 212,94 194,138" fill="', sd, '" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>'
        ));
    }

    function renderHorns(uint256 id) public pure returns (string memory) {
        uint256 ht = _rng(id, 4) % 7;
        if (ht == 0) return "";
        string memory hc = _hornColor(id);
        if (ht == 1) return _hornSingle(hc);
        if (ht == 2) return _hornTwinShort(hc);
        if (ht == 3) return _hornTwinLong(hc);
        if (ht == 4) return _hornCurved(hc);
        if (ht == 5) return _hornCrown(hc);
        return _hornBroken(hc);
    }

    function _hornSingle(string memory hc) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<polygon points="142,72 158,72 150,24" fill="', hc, '" stroke="rgba(0,0,0,0.18)" stroke-width="0.6"/>',
            '<polygon points="142,72 150,24 147,34" fill="rgba(0,0,0,0.25)" stroke="none"/>',
            '<polygon points="147,69 150,28 153,38" fill="rgba(255,255,255,0.2)" stroke="none"/>'
        ));
    }

    function _hornTwinShort(string memory hc) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<polygon points="115,82 129,82 121,46" fill="', hc, '" stroke="rgba(0,0,0,0.18)" stroke-width="0.6"/>',
            '<polygon points="115,82 121,46 113,58" fill="rgba(0,0,0,0.25)" stroke="none"/>',
            '<polygon points="171,82 185,82 179,46" fill="', hc, '" stroke="rgba(0,0,0,0.18)" stroke-width="0.6"/>',
            '<polygon points="179,46 185,82 187,58" fill="rgba(0,0,0,0.25)" stroke="none"/>',
            '<polygon points="118,80 121,50 124,60" fill="rgba(255,255,255,0.18)" stroke="none"/>',
            '<polygon points="176,80 179,50 182,60" fill="rgba(255,255,255,0.18)" stroke="none"/>'
        ));
    }

    function _hornTwinLong(string memory hc) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<polygon points="112,86 128,86 120,5" fill="', hc, '" stroke="rgba(0,0,0,0.18)" stroke-width="0.6"/>',
            '<polygon points="112,86 120,5 110,28" fill="rgba(0,0,0,0.28)" stroke="none"/>',
            '<polygon points="172,86 188,86 180,5" fill="', hc, '" stroke="rgba(0,0,0,0.18)" stroke-width="0.6"/>',
            '<polygon points="180,5 188,86 190,28" fill="rgba(0,0,0,0.28)" stroke="none"/>',
            '<polygon points="116,84 120,10 124,22" fill="rgba(255,255,255,0.15)" stroke="none"/>',
            '<polygon points="176,84 180,10 184,22" fill="rgba(255,255,255,0.15)" stroke="none"/>'
        ));
    }

    function _hornCurved(string memory hc) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<path d="M120,82 Q88,52 104,22 L112,28 Q98,52 128,79 Z" fill="', hc, '" stroke="rgba(0,0,0,0.2)" stroke-width="0.5"/>',
            '<path d="M180,82 Q212,52 196,22 L188,28 Q202,52 172,79 Z" fill="', hc, '" stroke="rgba(0,0,0,0.2)" stroke-width="0.5"/>',
            '<path d="M122,80 Q94,52 108,26 L112,28 Q100,52 126,78 Z" fill="rgba(255,255,255,0.12)" stroke="none"/>',
            '<path d="M178,80 Q206,52 192,26 L188,28 Q200,52 174,78 Z" fill="rgba(255,255,255,0.12)" stroke="none"/>'
        ));
    }

    function _hornCrown(string memory hc) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<polygon points="110,82 120,82 115,50" fill="', hc, '" stroke="rgba(0,0,0,0.18)" stroke-width="0.6"/>',
            '<polygon points="128,82 138,82 133,40" fill="', hc, '" stroke="rgba(0,0,0,0.18)" stroke-width="0.6"/>',
            '<polygon points="145,82 155,82 150,35" fill="', hc, '" stroke="rgba(0,0,0,0.18)" stroke-width="0.6"/>',
            '<polygon points="162,82 172,82 167,40" fill="', hc, '" stroke="rgba(0,0,0,0.18)" stroke-width="0.6"/>',
            '<polygon points="180,82 190,82 185,50" fill="', hc, '" stroke="rgba(0,0,0,0.18)" stroke-width="0.6"/>'
        ));
    }

    function _hornBroken(string memory hc) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<polygon points="118,82 132,82 124,48" fill="', hc, '" stroke="rgba(0,0,0,0.18)" stroke-width="0.6"/>',
            '<polygon points="118,82 124,48 116,60" fill="rgba(0,0,0,0.25)" stroke="none"/>',
            '<polygon points="168,82 182,82 176,52" fill="', hc, '" stroke="rgba(0,0,0,0.18)" stroke-width="0.6"/>',
            '<polygon points="168,82 176,52 166,62" fill="rgba(0,0,0,0.25)" stroke="none"/>',
            '<line x1="166" y1="58" x2="184" y2="54" stroke="rgba(0,0,0,0.5)" stroke-width="1.5"/>'
        ));
    }

    function renderHair(uint256 id) public pure returns (string memory) {
        uint256 ht = _rng(id, 7) % 7;
        if (ht == 0) return "";
        string memory hc = _hairColor(id);
        if (ht == 1) return _hairWild(hc);
        if (ht == 2) return _hairMohawk(hc);
        if (ht == 3) return _hairTopKnot(hc);
        if (ht == 4) return _hairSpiky(hc);
        if (ht == 5) return _hairFlowing(hc);
        return _hairBraided(hc);
    }

    function _hairWild(string memory hc) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<polygon points="105,84 113,84 118,160 110,162" fill="', hc, '" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<polygon points="120,80 128,80 130,155 122,157" fill="', hc, '" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<polygon points="145,78 153,78 152,154 144,156" fill="', hc, '" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<polygon points="170,80 178,80 172,155 164,157" fill="', hc, '" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<polygon points="185,84 193,84 184,160 176,162" fill="', hc, '" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>'
        ));
    }

    function _hairMohawk(string memory hc) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<polygon points="142,84 158,84 155,14 145,14" fill="', hc, '" stroke="rgba(0,0,0,0.18)" stroke-width="0.6"/>',
            '<polygon points="146,84 154,84 152,18 148,18" fill="rgba(255,255,255,0.15)" stroke="none"/>'
        ));
    }

    function _hairTopKnot(string memory hc) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<ellipse cx="150" cy="62" rx="14" ry="18" fill="', hc, '" stroke="rgba(0,0,0,0.18)" stroke-width="0.6"/>',
            '<ellipse cx="148" cy="58" rx="8" ry="10" fill="rgba(255,255,255,0.15)" stroke="none"/>',
            '<rect x="136" y="69" width="28" height="5" fill="#FFD700" stroke="rgba(0,0,0,0.2)" stroke-width="0.5"/>'
        ));
    }

    function _hairSpiky(string memory hc) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<polygon points="128,90 136,90 118,38" fill="', hc, '" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<polygon points="138,86 146,86 132,28" fill="', hc, '" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<polygon points="147,84 155,84 150,20" fill="', hc, '" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<polygon points="155,86 163,86 168,28" fill="', hc, '" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<polygon points="164,90 172,90 182,38" fill="', hc, '" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>'
        ));
    }

    function _hairFlowing(string memory hc) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<path d="M102,90 Q86,132 92,195 L106,192 Q100,130 116,96 Z" fill="', hc, '" stroke="rgba(0,0,0,0.12)" stroke-width="0.5"/>',
            '<path d="M198,90 Q214,132 208,195 L194,192 Q200,130 184,96 Z" fill="', hc, '" stroke="rgba(0,0,0,0.12)" stroke-width="0.5"/>',
            '<ellipse cx="150" cy="80" rx="50" ry="18" fill="', hc, '" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>'
        ));
    }

    function _hairBraided(string memory hc) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<ellipse cx="140" cy="84" rx="8" ry="9" fill="', hc, '" stroke="rgba(0,0,0,0.1)" stroke-width="0.5"/>',
            '<ellipse cx="160" cy="91" rx="8" ry="9" fill="', hc, '" stroke="rgba(0,0,0,0.1)" stroke-width="0.5"/>',
            '<ellipse cx="140" cy="105" rx="8" ry="9" fill="', hc, '" stroke="rgba(0,0,0,0.1)" stroke-width="0.5"/>',
            '<ellipse cx="160" cy="112" rx="8" ry="9" fill="', hc, '" stroke="rgba(0,0,0,0.1)" stroke-width="0.5"/>',
            '<ellipse cx="140" cy="126" rx="8" ry="9" fill="', hc, '" stroke="rgba(0,0,0,0.1)" stroke-width="0.5"/>',
            '<ellipse cx="160" cy="133" rx="8" ry="9" fill="', hc, '" stroke="rgba(0,0,0,0.1)" stroke-width="0.5"/>'
        ));
    }
}
