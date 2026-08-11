// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

/// @title ONI Renderer 2 — Body + Outfit + Legs + Arms + Weapon
contract ONIRenderer2 {

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

    function outfitName(uint256 id) public pure returns (string memory) {
        uint256 t = _rng(id, 6) % 7;
        if (t == 0) return "Shirtless";
        if (t == 1) return "Kimono";
        if (t == 2) return "Armor";
        if (t == 3) return "Robe";
        if (t == 4) return "ChainMail";
        if (t == 5) return "Priest";
        return "Void";
    }

    function weaponName(uint256 id) public pure returns (string memory) {
        uint256 t = _rng(id, 9) % 7;
        if (t == 0) return "None";
        if (t == 1) return "Kanabo";
        if (t == 2) return "Katana";
        if (t == 3) return "Spear";
        if (t == 4) return "Chains";
        if (t == 5) return "Fire";
        return "Twin Blades";
    }

    function _outfitColor(uint256 t) internal pure returns (string memory) {
        if (t == 0) return "#1a0808";
        if (t == 1) return "#AA0022";
        if (t == 2) return "#1a1a2a";
        if (t == 3) return "#2a1a00";
        if (t == 4) return "#333333";
        if (t == 5) return "#eeeeee";
        return "#0a0a0a";
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

    function renderLegs(uint256 id) public pure returns (string memory) {
        uint256 ot = _rng(id, 6) % 7;
        string memory lc = (ot == 0 || ot == 5) ? _skinMid(id) : "#1a1a2a";
        return string(abi.encodePacked(
            '<polygon points="104,235 134,235 124,290 82,290" fill="', lc, '" stroke="rgba(0,0,0,0.18)" stroke-width="0.6"/>',
            '<polygon points="104,235 124,290 106,290 96,235" fill="', lc, '" fill-opacity="0.8" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<polygon points="166,235 196,235 218,290 196,290" fill="', lc, '" stroke="rgba(0,0,0,0.18)" stroke-width="0.6"/>',
            '<polygon points="166,235 196,290 174,290 164,235" fill="', lc, '" fill-opacity="0.9" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<polygon points="100,290 132,290 116,308 82,308" fill="#111111" stroke="rgba(0,0,0,0.3)" stroke-width="0.6"/>',
            '<polygon points="100,298 130,298 115,316 82,316" fill="#333333" stroke="none"/>',
            '<polygon points="168,290 200,290 218,308 184,308" fill="#111111" stroke="rgba(0,0,0,0.3)" stroke-width="0.6"/>',
            '<polygon points="170,298 200,298 215,316 185,316" fill="#333333" stroke="none"/>',
            '<line x1="156" y1="290" x2="144" y2="276" stroke="#8B6914" stroke-width="1.5"/>',
            '<line x1="194" y1="290" x2="206" y2="276" stroke="#8B6914" stroke-width="1.5"/>'
        ));
    }

    function renderBody(uint256 id) public pure returns (string memory) {
        uint256 ot = _rng(id, 6) % 7;
        string memory oc = _outfitColor(ot);
        string memory sk = _skinBase(id);
        string memory sm = _skinMid(id);
        string memory ec = _eyeColor(id);

        if (ot == 0) return _bodyShirtless(sk, sm);
        if (ot == 1) return _bodyKimono(oc, ec);
        if (ot == 2) return _bodyArmor(oc, ec);
        if (ot == 3) return _bodyRobe(oc);
        if (ot == 4) return _bodyChainmail(oc);
        if (ot == 5) return _bodyPriest(oc);
        return _bodyVoid(ec);
    }

    function _bodyShirtless(string memory sk, string memory sm) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<polygon points="98,135 202,135 200,215 100,215" fill="', sk, '" stroke="rgba(0,0,0,0.18)" stroke-width="0.6"/>',
            '<polygon points="98,135 150,175 100,215" fill="', sm, '" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<polygon points="202,135 150,175 200,215" fill="', sm, '" fill-opacity="0.7" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<polygon points="128,155 150,170 134,185" fill="rgba(0,0,0,0.15)" stroke="none"/>',
            '<polygon points="172,155 150,170 166,185" fill="rgba(0,0,0,0.15)" stroke="none"/>',
            '<polygon points="130,185 150,198 136,208" fill="rgba(0,0,0,0.1)" stroke="none"/>',
            '<polygon points="170,185 150,198 164,208" fill="rgba(0,0,0,0.1)" stroke="none"/>',
            '<line x1="150" y1="138" x2="150" y2="218" stroke="rgba(0,0,0,0.1)" stroke-width="1"/>'
        ));
    }

    function _bodyKimono(string memory oc, string memory ec) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<polygon points="95,132 205,132 200,218 100,218" fill="', oc, '" stroke="rgba(0,0,0,0.18)" stroke-width="0.6"/>',
            '<polygon points="95,132 150,178 100,218" fill="', oc, '" fill-opacity="0.7" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<polygon points="205,132 150,178 200,218" fill="rgba(255,255,255,0.08)" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<polygon points="122,140 128,140 120,168" fill="', ec, '" fill-opacity="0.25" stroke="none"/>',
            '<polygon points="172,140 178,140 180,168" fill="', ec, '" fill-opacity="0.25" stroke="none"/>',
            '<polygon points="142,208 158,208 154,218 146,218" fill="#FFD700" stroke="rgba(0,0,0,0.2)" stroke-width="0.5"/>',
            '<polygon points="98,208 202,208 200,218 100,218" fill="rgba(255,255,255,0.12)" stroke="none"/>'
        ));
    }

    function _bodyArmor(string memory oc, string memory ec) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<polygon points="96,130 204,130 200,218 100,218" fill="rgba(255,255,255,0.08)" stroke="rgba(0,0,0,0.18)" stroke-width="0.6"/>',
            '<polygon points="96,130 150,178 100,218" fill="', oc, '" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<polygon points="204,130 150,178 200,218" fill="rgba(0,0,0,0.2)" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<polygon points="112,140 188,140 183,182 117,182" fill="rgba(255,255,255,0.06)" stroke="rgba(255,255,255,0.15)" stroke-width="0.8"/>',
            '<polygon points="117,182 183,182 150,200" fill="rgba(255,255,255,0.04)" stroke="rgba(255,255,255,0.1)" stroke-width="0.5"/>',
            '<polygon points="145,152 155,152 158,162 150,168 142,162" fill="', ec, '" stroke="rgba(255,255,255,0.3)" stroke-width="0.5"/>',
            '<polygon points="145,152 155,152 150,158" fill="rgba(255,255,255,0.4)" stroke="none"/>'
        ));
    }

    function _bodyRobe(string memory oc) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<polygon points="92,130 208,130 205,228 95,228" fill="', oc, '" stroke="rgba(0,0,0,0.18)" stroke-width="0.6"/>',
            '<polygon points="92,130 150,182 95,228" fill="rgba(0,0,0,0.22)" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<polygon points="208,130 150,182 205,228" fill="rgba(255,255,255,0.06)" stroke="rgba(0,0,0,0.1)" stroke-width="0.5"/>',
            '<polygon points="118,175 132,165 114,152" fill="rgba(0,0,0,0.3)" stroke="none"/>',
            '<polygon points="182,152 168,162 172,178" fill="rgba(0,0,0,0.3)" stroke="none"/>'
        ));
    }

    function _bodyChainmail(string memory oc) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<polygon points="98,132 202,132 198,218 102,218" fill="', oc, '" stroke="rgba(0,0,0,0.18)" stroke-width="0.6"/>',
            '<polygon points="98,132 150,175 102,218" fill="rgba(255,255,255,0.05)" stroke="rgba(0,0,0,0.1)" stroke-width="0.5"/>',
            '<circle cx="120" cy="145" r="5" fill="none" stroke="rgba(150,150,170,0.25)" stroke-width="1"/>',
            '<circle cx="142" cy="145" r="5" fill="none" stroke="rgba(150,150,170,0.25)" stroke-width="1"/>',
            '<circle cx="164" cy="145" r="5" fill="none" stroke="rgba(150,150,170,0.25)" stroke-width="1"/>',
            '<circle cx="120" cy="167" r="5" fill="none" stroke="rgba(150,150,170,0.25)" stroke-width="1"/>',
            '<circle cx="142" cy="167" r="5" fill="none" stroke="rgba(150,150,170,0.25)" stroke-width="1"/>',
            '<circle cx="164" cy="167" r="5" fill="none" stroke="rgba(150,150,170,0.25)" stroke-width="1"/>',
            '<circle cx="120" cy="189" r="5" fill="none" stroke="rgba(150,150,170,0.25)" stroke-width="1"/>',
            '<circle cx="142" cy="189" r="5" fill="none" stroke="rgba(150,150,170,0.25)" stroke-width="1"/>',
            '<circle cx="164" cy="189" r="5" fill="none" stroke="rgba(150,150,170,0.25)" stroke-width="1"/>'
        ));
    }

    function _bodyPriest(string memory oc) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<polygon points="100,130 200,130 196,218 104,218" fill="', oc, '" stroke="rgba(0,0,0,0.18)" stroke-width="0.6"/>',
            '<polygon points="100,130 150,172 104,218" fill="rgba(0,0,0,0.18)" stroke="rgba(0,0,0,0.1)" stroke-width="0.5"/>',
            '<polygon points="138,130 162,130 150,158" fill="rgba(255,255,255,0.88)" stroke="rgba(0,0,0,0.1)" stroke-width="0.5"/>',
            '<circle cx="126" cy="172" r="3" fill="#8B4513"/>',
            '<circle cx="138" cy="178" r="3" fill="#CC0000"/>',
            '<circle cx="150" cy="172" r="3" fill="#FFD700"/>',
            '<circle cx="162" cy="178" r="3" fill="#8B4513"/>',
            '<circle cx="174" cy="172" r="3" fill="#CC0000"/>'
        ));
    }

    function _bodyVoid(string memory ec) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<polygon points="95,130 205,130 200,218 100,218" fill="#0a0a0a" stroke="rgba(0,0,0,0.18)" stroke-width="0.6"/>',
            '<polygon points="95,130 150,174 100,218" fill="#050505" stroke="rgba(0,0,0,0.1)" stroke-width="0.5"/>',
            '<polygon points="205,130 150,174 200,218" fill="#111111" stroke="rgba(0,0,0,0.1)" stroke-width="0.5"/>',
            '<circle cx="120" cy="160" r="3" fill="', ec, '" fill-opacity="0.6"/>',
            '<circle cx="150" cy="150" r="2" fill="', ec, '" fill-opacity="0.5"/>',
            '<circle cx="178" cy="165" r="3" fill="', ec, '" fill-opacity="0.6"/>',
            '<circle cx="135" cy="185" r="2" fill="', ec, '" fill-opacity="0.4"/>',
            '<circle cx="165" cy="190" r="2" fill="', ec, '" fill-opacity="0.4"/>'
        ));
    }

    function renderArms(uint256 id) public pure returns (string memory) {
        uint256 ot = _rng(id, 6) % 7;
        string memory ac = ot == 0 ? _skinBase(id) : _outfitColor(ot);
        string memory ad = ot == 0 ? _skinMid(id) : ac;
        return string(abi.encodePacked(
            '<polygon points="98,132 76,158 83,232 98,236" fill="', ac, '" stroke="rgba(0,0,0,0.18)" stroke-width="0.6"/>',
            '<polygon points="98,132 83,232 98,236 102,140" fill="', ad, '" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<polygon points="202,132 224,158 217,232 202,236" fill="', ac, '" stroke="rgba(0,0,0,0.18)" stroke-width="0.6"/>',
            '<polygon points="202,132 217,232 202,236 198,140" fill="rgba(255,255,255,0.1)" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<polygon points="72,220 88,220 81,246 65,246" fill="#FFD700" stroke="rgba(0,0,0,0.2)" stroke-width="0.5"/>',
            '<polygon points="212,220 228,220 235,246 219,246" fill="#FFD700" stroke="rgba(0,0,0,0.2)" stroke-width="0.5"/>',
            '<polygon points="64,232 80,232 81,246 65,246" fill="', _skinBase(id), '" stroke="rgba(0,0,0,0.18)" stroke-width="0.6"/>',
            '<polygon points="64,246 80,246 81,258 65,258" fill="', _skinMid(id), '" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>',
            '<polygon points="220,232 236,232 235,246 219,246" fill="', _skinBase(id), '" stroke="rgba(0,0,0,0.18)" stroke-width="0.6"/>',
            '<polygon points="219,246 235,246 236,258 220,258" fill="', _skinMid(id), '" stroke="rgba(0,0,0,0.15)" stroke-width="0.5"/>'
        ));
    }

    function renderWeapon(uint256 id) public pure returns (string memory) {
        uint256 wt = _rng(id, 9) % 7;
        string memory ec = _eyeColor(id);
        if (wt == 0) return "";
        if (wt == 1) return _weaponKanabo();
        if (wt == 2) return _weaponKatana();
        if (wt == 3) return _weaponSpear();
        if (wt == 4) return _weaponChains();
        if (wt == 5) return _weaponFire(ec);
        return _weaponTwinBlades();
    }

    function _weaponKanabo() internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<rect x="222" y="105" width="13" height="115" fill="#2a1a0a" rx="2"/>',
            '<circle cx="224" cy="118" r="3" fill="#777"/>',
            '<circle cx="232" cy="118" r="3" fill="#999"/>',
            '<circle cx="224" cy="136" r="3" fill="#777"/>',
            '<circle cx="232" cy="136" r="3" fill="#999"/>',
            '<circle cx="224" cy="154" r="3" fill="#777"/>',
            '<circle cx="232" cy="154" r="3" fill="#999"/>',
            '<circle cx="224" cy="172" r="3" fill="#777"/>',
            '<circle cx="232" cy="172" r="3" fill="#999"/>',
            '<circle cx="228" cy="103" r="7" fill="#888"/>',
            '<circle cx="228" cy="103" r="5" fill="#aaa"/>'
        ));
    }

    function _weaponKatana() internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<rect x="222" y="208" width="8" height="28" fill="#8B6914" rx="1"/>',
            '<rect x="220" y="204" width="12" height="5" fill="#FFD700"/>',
            '<line x1="226" y1="202" x2="230" y2="85" stroke="#d8d8f0" stroke-width="2.5"/>',
            '<line x1="225" y1="202" x2="229" y2="85" stroke="rgba(255,255,255,0.3)" stroke-width="1"/>',
            '<circle cx="230" cy="85" r="2" fill="#ffffff"/>'
        ));
    }

    function _weaponSpear() internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<line x1="225" y1="238" x2="220" y2="75" stroke="#5a3a10" stroke-width="4"/>',
            '<polygon points="218,75 222,40 226,75" fill="#888" stroke="rgba(0,0,0,0.3)" stroke-width="0.5"/>',
            '<polygon points="219,75 222,45 225,75" fill="#aaa" stroke="none"/>'
        ));
    }

    function _weaponChains() internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<circle cx="220" cy="242" r="4" fill="none" stroke="#888" stroke-width="2"/>',
            '<circle cx="227" cy="226" r="4" fill="none" stroke="#888" stroke-width="2"/>',
            '<circle cx="234" cy="210" r="4" fill="none" stroke="#888" stroke-width="2"/>',
            '<circle cx="241" cy="194" r="4" fill="none" stroke="#888" stroke-width="2"/>',
            '<circle cx="248" cy="178" r="4" fill="none" stroke="#888" stroke-width="2"/>',
            '<circle cx="252" cy="158" r="9" fill="#666"/>',
            '<circle cx="252" cy="158" r="6" fill="#888"/>'
        ));
    }

    function _weaponFire(string memory ec) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<circle cx="218" cy="246" r="22" fill="#FFFF00" fill-opacity="0.2"/>',
            '<circle cx="218" cy="246" r="16" fill="#FF8800" fill-opacity="0.25"/>',
            '<circle cx="218" cy="246" r="10" fill="#FF4400" fill-opacity="0.3"/>',
            '<circle cx="218" cy="246" r="5" fill="', ec, '" fill-opacity="0.6"/>',
            '<circle cx="218" cy="246" r="2" fill="#ffffff" fill-opacity="0.8"/>'
        ));
    }

    function _weaponTwinBlades() internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<rect x="58" y="208" width="7" height="25" fill="#8B6914" rx="1"/>',
            '<rect x="57" y="204" width="9" height="4" fill="#FFD700"/>',
            '<line x1="61" y1="202" x2="55" y2="105" stroke="#d8d8f0" stroke-width="2.5"/>',
            '<rect x="222" y="208" width="7" height="25" fill="#8B6914" rx="1"/>',
            '<rect x="221" y="204" width="9" height="4" fill="#FFD700"/>',
            '<line x1="226" y1="202" x2="232" y2="105" stroke="#d8d8f0" stroke-width="2.5"/>'
        ));
    }
}
