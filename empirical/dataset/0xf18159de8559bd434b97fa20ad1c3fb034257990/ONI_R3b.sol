// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

/// @title ONI Renderer 3b — Eyes + Nose + Mouth + Face Tattoo
contract ONIRenderer3b {

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

    function renderEyes(uint256 id) public pure returns (string memory) {
        uint256 et = _rng(id, 5) % 8;
        string memory ec = _eyeColor(id);
        string memory left = _drawEye(136, 137, et, ec);
        string memory right = _drawEye(164, 137, et, ec);
        return string(abi.encodePacked(left, right));
    }

    function _drawEye(uint256 ex, uint256 ey, uint256 et, string memory ec) internal pure returns (string memory) {
        string memory sx = _n(ex); string memory sy = _n(ey);
        if (et == 0) return string(abi.encodePacked(
            '<ellipse cx="',sx,'" cy="',sy,'" rx="10" ry="8" fill="#fff"/>',
            '<ellipse cx="',sx,'" cy="',sy,'" rx="8" ry="7" fill="',ec,'"/>',
            '<ellipse cx="',sx,'" cy="',sy,'" rx="4" ry="5" fill="#000"/>',
            '<ellipse cx="',_n(ex-4),'" cy="',_n(ey-3),'" rx="3" ry="4" fill="rgba(255,255,255,0.85)"/>',
            '<circle cx="',_n(ex+3),'" cy="',_n(ey+1),'" r="1.5" fill="rgba(255,255,255,0.45)"/>'
        ));
        if (et == 1) return string(abi.encodePacked(
            '<ellipse cx="',sx,'" cy="',sy,'" rx="10" ry="8" fill="#fff"/>',
            '<circle cx="',sx,'" cy="',sy,'" r="8" fill="none" stroke="',ec,'" stroke-width="1.5"/>',
            '<circle cx="',sx,'" cy="',sy,'" r="5" fill="none" stroke="',ec,'" stroke-width="1.2"/>',
            '<circle cx="',sx,'" cy="',sy,'" r="2" fill="',ec,'"/>'
        ));
        if (et == 2) return string(abi.encodePacked(
            '<ellipse cx="',sx,'" cy="',sy,'" rx="10" ry="8" fill="#fff"/>',
            '<ellipse cx="',sx,'" cy="',sy,'" rx="9" ry="7" fill="#FFFF00"/>',
            '<ellipse cx="',sx,'" cy="',sy,'" rx="6" ry="5" fill="#FF4400"/>',
            '<ellipse cx="',sx,'" cy="',sy,'" rx="3" ry="4" fill="#FF0000"/>',
            '<ellipse cx="',sx,'" cy="',sy,'" rx="1.5" ry="2" fill="#000"/>'
        ));
        if (et == 3) return string(abi.encodePacked(
            '<ellipse cx="',sx,'" cy="',sy,'" rx="10" ry="8" fill="#fff"/>',
            '<polygon points="',_n(ex),',',_n(ey-8),' ',_n(ex+8),',',sy,' ',_n(ex),',',_n(ey+6),' ',_n(ex-8),',',sy,'" fill="',ec,'"/>',
            '<polygon points="',_n(ex),',',_n(ey-8),' ',_n(ex+4),',',sy,' ',_n(ex),',',_n(ey-3),'" fill="rgba(255,255,255,0.45)"/>'
        ));
        if (et == 4) return string(abi.encodePacked(
            '<ellipse cx="',sx,'" cy="',sy,'" rx="10" ry="8" fill="#fff"/>',
            '<polygon points="',
            _n(ex),',',_n(ey-7),' ',_n(ex+2),',',_n(ey-3),' ',
            _n(ex+7),',',_n(ey-3),' ',_n(ex+4),',',_n(ey+1),' ',
            _n(ex+5),',',_n(ey+6),' ',_n(ex),',',_n(ey+3),' ',
            _n(ex-5),',',_n(ey+6),' ',_n(ex-4),',',_n(ey+1),' ',
            _n(ex-7),',',_n(ey-3),' ',_n(ex-2),',',_n(ey-3),
            '" fill="',ec,'"/>'
        ));
        if (et == 5) return string(abi.encodePacked(
            '<ellipse cx="',sx,'" cy="',sy,'" rx="10" ry="8" fill="#fff"/>',
            '<line x1="',sx,'" y1="',sy,'" x2="',_n(ex+9),'" y2="',sy,'" stroke="rgba(255,0,0,0.4)" stroke-width="0.7"/>',
            '<line x1="',sx,'" y1="',sy,'" x2="',_n(ex-9),'" y2="',sy,'" stroke="rgba(255,0,0,0.4)" stroke-width="0.7"/>',
            '<line x1="',sx,'" y1="',sy,'" x2="',sx,'" y2="',_n(ey-8),'" stroke="rgba(255,0,0,0.4)" stroke-width="0.7"/>',
            '<ellipse cx="',sx,'" cy="',sy,'" rx="4" ry="5" fill="',ec,'"/>',
            '<ellipse cx="',sx,'" cy="',sy,'" rx="2" ry="3" fill="#000"/>'
        ));
        if (et == 6) return string(abi.encodePacked(
            '<ellipse cx="',sx,'" cy="',sy,'" rx="10" ry="8" fill="',ec,'"/>',
            '<ellipse cx="',_n(ex-3),'" cy="',_n(ey-3),'" rx="3" ry="3" fill="rgba(255,255,255,0.18)"/>'
        ));
        return string(abi.encodePacked(
            '<ellipse cx="',sx,'" cy="',sy,'" rx="14" ry="12" fill="',ec,'" fill-opacity="0.25"/>',
            '<ellipse cx="',sx,'" cy="',sy,'" rx="10" ry="8" fill="',ec,'" fill-opacity="0.7"/>',
            '<ellipse cx="',sx,'" cy="',sy,'" rx="5" ry="5" fill="#fff" fill-opacity="0.8"/>',
            '<ellipse cx="',sx,'" cy="',sy,'" rx="2" ry="2" fill="#000"/>'
        ));
    }

    function renderNose(uint256 id) public pure returns (string memory) {
        uint256 ht = _rng(id, 2) % 8;
        string memory sd = _skinDark(id);
        if (ht == 2) return string(abi.encodePacked(
            '<polygon points="144,152 156,152 150,172" fill="',sd,'" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<polygon points="144,152 150,172 146,165" fill="rgba(0,0,0,0.25)" stroke="none"/>'
        ));
        return string(abi.encodePacked(
            '<polygon points="144,148 156,148 150,160" fill="',sd,'" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<polygon points="144,148 150,160 146,154" fill="rgba(0,0,0,0.22)" stroke="none"/>'
        ));
    }

    function renderMouth(uint256 id) public pure returns (string memory) {
        uint256 mt = _rng(id, 8) % 6;
        string memory sd = _skinDark(id);
        if (mt == 0) return string(abi.encodePacked(
            '<polygon points="128,166 172,166 150,184" fill="',sd,'" fill-opacity="0.8" stroke="rgba(0,0,0,0.18)" stroke-width="0.6"/>',
            '<polygon points="132,166 142,166 136,184" fill="#ffffff" stroke="rgba(0,0,0,0.2)" stroke-width="0.5"/>',
            '<polygon points="158,166 168,166 164,184" fill="#ffffff" stroke="rgba(0,0,0,0.2)" stroke-width="0.5"/>',
            '<polygon points="142,166 158,166 150,178" fill="rgba(180,20,20,0.5)" stroke="none"/>'
        ));
        if (mt == 1) return string(abi.encodePacked(
            '<polygon points="128,166 172,166 150,181" fill="',sd,'" fill-opacity="0.8" stroke="rgba(0,0,0,0.18)" stroke-width="0.6"/>',
            '<polygon points="128,166 138,168 134,188" fill="#fffaf0" stroke="rgba(0,0,0,0.2)" stroke-width="0.5"/>',
            '<polygon points="162,168 172,166 166,188" fill="#fffaf0" stroke="rgba(0,0,0,0.2)" stroke-width="0.5"/>'
        ));
        if (mt == 2) return string(abi.encodePacked(
            '<line x1="130" y1="174" x2="170" y2="174" stroke="rgba(0,0,0,0.6)" stroke-width="1.5"/>',
            '<line x1="136" y1="170" x2="136" y2="178" stroke="rgba(0,0,0,0.5)" stroke-width="1.2"/>',
            '<line x1="143" y1="170" x2="143" y2="178" stroke="rgba(0,0,0,0.5)" stroke-width="1.2"/>',
            '<line x1="150" y1="170" x2="150" y2="178" stroke="rgba(0,0,0,0.5)" stroke-width="1.2"/>',
            '<line x1="157" y1="170" x2="157" y2="178" stroke="rgba(0,0,0,0.5)" stroke-width="1.2"/>',
            '<line x1="164" y1="170" x2="164" y2="178" stroke="rgba(0,0,0,0.5)" stroke-width="1.2"/>'
        ));
        if (mt == 3) return string(abi.encodePacked(
            '<ellipse cx="150" cy="176" rx="22" ry="15" fill="rgba(0,0,0,0.8)"/>',
            '<ellipse cx="150" cy="178" rx="16" ry="10" fill="rgba(180,0,25,0.5)"/>',
            '<polygon points="136,166 142,166 139,176" fill="#fff" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<polygon points="143,166 149,166 146,176" fill="#fff" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<polygon points="151,166 157,166 154,176" fill="#fff" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<polygon points="158,166 164,166 161,176" fill="#fff" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<polygon points="136,186 142,186 139,176" fill="#fff" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<polygon points="151,186 157,186 154,176" fill="#fff" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>'
        ));
        if (mt == 4) return string(abi.encodePacked(
            '<path d="M135,174 Q155,170 168,164" fill="none" stroke="',sd,'" stroke-width="2" stroke-opacity="0.8"/>',
            '<circle cx="166" cy="165" r="3" fill="#ffffff"/>'
        ));
        return '<line x1="136" y1="174" x2="164" y2="174" stroke="rgba(0,0,0,0.5)" stroke-width="1.5"/>';
    }

    function renderFaceTat(uint256 id) public pure returns (string memory) {
        uint256 ftt = _rng(id, 10) % 6;
        if (ftt == 0) return "";
        string memory ec = _eyeColor(id);
        if (ftt == 1) return string(abi.encodePacked(
            '<path d="M110,116 L120,128 L108,140" fill="none" stroke="',ec,'" stroke-width="1.2" stroke-opacity="0.7"/>',
            '<path d="M190,116 L180,128 L192,140" fill="none" stroke="',ec,'" stroke-width="1.2" stroke-opacity="0.7"/>'
        ));
        if (ftt == 2) return string(abi.encodePacked(
            '<text x="186" y="114" fill="',ec,'" font-size="13" font-family="serif" fill-opacity="0.7">&#39340;</text>'
        ));
        if (ftt == 3) return string(abi.encodePacked(
            '<path d="M112,110 Q104,120 112,132 Q120,120 112,110" fill="none" stroke="',ec,'" stroke-width="1.5" stroke-opacity="0.7"/>',
            '<path d="M188,110 Q196,120 188,132 Q180,120 188,110" fill="none" stroke="',ec,'" stroke-width="1.5" stroke-opacity="0.7"/>'
        ));
        if (ftt == 4) return string(abi.encodePacked(
            '<polygon points="112,110 120,118 112,126 104,118" fill="none" stroke="',ec,'" stroke-width="1" stroke-opacity="0.7"/>',
            '<polygon points="188,110 196,118 188,126 180,118" fill="none" stroke="',ec,'" stroke-width="1" stroke-opacity="0.7"/>'
        ));
        return string(abi.encodePacked(
            '<text x="114" y="132" fill="',ec,'" font-size="11" font-family="serif" fill-opacity="0.65">&#5792;</text>',
            '<text x="180" y="132" fill="',ec,'" font-size="11" font-family="serif" fill-opacity="0.65">&#5794;</text>'
        ));
    }
}
