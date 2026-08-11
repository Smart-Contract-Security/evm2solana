// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

struct NoisieTraits {
    uint8 gender; uint8 skinIdx; uint8 hairCI; uint8 faceShape;
    uint8 hairStyle; uint8 browStyle; uint8 eyeStyle; uint8 eyeSize;
    uint8 noseStyle; uint8 lipStyle; uint8 lipFull; uint8 expr;
    uint8 acc; uint8 glasses; uint8 beard; uint8 makeup;
    uint8 freckles; uint8 age; uint8 mole; uint8 scar;
    uint8 dimples; uint8 chinShape;
}

contract NoisiesR1 {
    address public owner;
    constructor() { owner = msg.sender; }

    string[8] private SK = [
        "#e8ddd0","#d8c8b8","#c8a888","#b88868",
        "#986848","#784830","#583820","#381808"
    ];
    string[6] private HC = [
        "#c8a850","#987040","#685030","#382818","#181008","#c0b8b0"
    ];
    string[6] private CC = [
        "#282018","#303830","#281820","#182028","#303020","#382808"
    ];

    function render(NoisieTraits memory t, uint256 seed) external view returns (string memory) {
        return string(abi.encodePacked(_bg(seed), _clothing(t, seed), _face(t), _hair(t)));
    }

    function _bg(uint256 seed) internal view returns (string memory) {
        uint8 v = uint8(seed % 4);
        string memory pat = "";
        if (v == 1) pat = '<line x1="0" y1="40" x2="120" y2="40" stroke="#d0c8c0" stroke-width="0.5" opacity="0.4"/><line x1="0" y1="80" x2="120" y2="80" stroke="#d0c8c0" stroke-width="0.5" opacity="0.4"/>';
        else if (v == 2) pat = '<circle cx="15" cy="15" r="10" fill="none" stroke="#ccc5bc" stroke-width="0.8" opacity="0.35"/><circle cx="105" cy="105" r="10" fill="none" stroke="#ccc5bc" stroke-width="0.8" opacity="0.35"/><circle cx="105" cy="15" r="7" fill="none" stroke="#ccc5bc" stroke-width="0.6" opacity="0.25"/><circle cx="15" cy="105" r="7" fill="none" stroke="#ccc5bc" stroke-width="0.6" opacity="0.25"/>';
        else if (v == 3) pat = '<path d="M0,0 L120,120 M0,40 L80,120 M40,0 L120,80" stroke="#cec6be" stroke-width="0.5" opacity="0.25"/>';
        return string(abi.encodePacked('<rect width="120" height="120" fill="#eae6e0"/>', pat));
    }

    function _clothing(NoisieTraits memory t, uint256 seed) internal view returns (string memory) {
        string memory cc = CC[seed % 6];
        string memory sk = SK[t.skinIdx];
        return string(abi.encodePacked(
            '<rect x="6" y="96" width="108" height="24" fill="', cc, '"/>',
            '<line x1="6" y1="96" x2="114" y2="96" stroke="#00000025" stroke-width="1"/>',
            '<rect x="42" y="87" width="36" height="12" fill="', sk, '"/>',
            '<line x1="42" y1="87" x2="42" y2="99" stroke="#00000015" stroke-width="1"/>',
            '<line x1="78" y1="87" x2="78" y2="99" stroke="#00000015" stroke-width="1"/>',
            '<polygon points="51,96 69,96 60,105" fill="', cc, '"/>',
            '<line x1="60" y1="96" x2="60" y2="120" stroke="#ffffff15" stroke-width="1"/>'
        ));
    }

    function _face(NoisieTraits memory t) internal view returns (string memory) {
        string memory sk = SK[t.skinIdx];
        uint256[5] memory rxA = [uint256(34),36,32,35,28];
        uint256[5] memory ryA = [uint256(40),37,37,43,46];
        uint256 rx = rxA[t.faceShape];
        uint256 ry = ryA[t.faceShape];
        return string(abi.encodePacked(
            '<ellipse cx="', _u(60-rx-4), '" cy="57" rx="5" ry="9" fill="', sk, '"/>',
            '<ellipse cx="', _u(60+rx+4), '" cy="57" rx="5" ry="9" fill="', sk, '"/>',
            '<ellipse cx="', _u(60-rx-4), '" cy="57" rx="3" ry="6" fill="#00000012"/>',
            '<ellipse cx="', _u(60+rx+4), '" cy="57" rx="3" ry="6" fill="#00000012"/>',
            '<ellipse cx="60" cy="54" rx="', _u(rx), '" ry="', _u(ry), '" fill="', sk, '"/>',
            '<ellipse cx="', _u(60-rx/3), '" cy="54" rx="', _u(rx/4+1), '" ry="', _u(ry*4/5), '" fill="#00000009"/>',
            '<ellipse cx="', _u(60+rx/3), '" cy="54" rx="', _u(rx/4+1), '" ry="', _u(ry*4/5), '" fill="#00000009"/>',
            '<ellipse cx="60" cy="', _u(54-ry/3), '" rx="', _u(rx/2), '" ry="', _u(ry/6+1), '" fill="#ffffff18"/>',
            '<ellipse cx="60" cy="', _u(54+ry*4/5), '" rx="', _u(rx/3), '" ry="', _u(ry/8+1), '" fill="#00000010"/>'
        ));
    }

    function _hair(NoisieTraits memory t) internal view returns (string memory) {
        string memory hc = HC[t.hairCI];
        if (t.hairStyle == 0) return _h0(hc);
        if (t.hairStyle == 1) return _h1(hc);
        if (t.hairStyle == 2) return _h2(hc);
        if (t.hairStyle == 3) return _h3(hc);
        if (t.hairStyle == 4) return _h4(hc, SK[t.skinIdx]);
        if (t.hairStyle == 5) return _h5(hc);
        if (t.hairStyle == 6) return _h6(hc);
        if (t.hairStyle == 7) return _h7(hc);
        if (t.hairStyle == 8) return _h8(hc);
        if (t.hairStyle == 9) return _h9(hc);
        if (t.hairStyle == 10) return _h10(hc);
        return _h11(hc);
    }

    function _h0(string memory hc) internal view returns (string memory) {
        return string(abi.encodePacked(
            '<ellipse cx="60" cy="24" rx="34" ry="16" fill="', hc, '"/>',
            '<rect x="26" y="24" width="68" height="12" fill="', hc, '"/>',
            '<line x1="52" y1="12" x2="52" y2="36" stroke="#ffffff20" stroke-width="1.5"/>',
            '<line x1="50" y1="12" x2="50" y2="34" stroke="#00000015" stroke-width="1"/>'
        ));
    }
    function _h1(string memory hc) internal view returns (string memory) {
        return string(abi.encodePacked(
            '<ellipse cx="60" cy="21" rx="36" ry="18" fill="', hc, '"/>',
            '<path d="M24,30 Q18,48 24,66 Q20,78 22,90" stroke="', hc, '" stroke-width="9" fill="none"/>',
            '<path d="M96,30 Q102,48 96,66 Q100,78 98,90" stroke="', hc, '" stroke-width="9" fill="none"/>',
            '<path d="M24,30 Q18,48 24,66" stroke="#ffffff15" stroke-width="2" fill="none"/>',
            '<path d="M96,30 Q102,48 96,66" stroke="#ffffff15" stroke-width="2" fill="none"/>'
        ));
    }
    function _h2(string memory hc) internal view returns (string memory) {
        return string(abi.encodePacked(
            '<ellipse cx="60" cy="18" rx="36" ry="18" fill="', hc, '"/>',
            '<path d="M24,24 Q18,60 22,96 Q20,108 18,114" stroke="', hc, '" stroke-width="10" fill="none"/>',
            '<path d="M96,24 Q102,60 98,96 Q100,108 102,114" stroke="', hc, '" stroke-width="10" fill="none"/>',
            '<path d="M24,24 L24,90" stroke="#ffffff12" stroke-width="2" fill="none"/>',
            '<path d="M96,24 L96,90" stroke="#ffffff12" stroke-width="2" fill="none"/>'
        ));
    }
    function _h3(string memory hc) internal view returns (string memory) {
        return string(abi.encodePacked(
            '<circle cx="60" cy="21" r="42" fill="', hc, '"/>',
            '<circle cx="28" cy="30" r="16" fill="', hc, '"/>',
            '<circle cx="92" cy="30" r="16" fill="', hc, '"/>',
            '<circle cx="44" cy="12" r="14" fill="', hc, '"/>',
            '<circle cx="76" cy="12" r="14" fill="', hc, '"/>',
            '<circle cx="60" cy="6" r="13" fill="', hc, '"/>'
        ));
    }
    function _h4(string memory hc, string memory sk) internal view returns (string memory) {
        return string(abi.encodePacked(
            '<ellipse cx="60" cy="24" rx="34" ry="14" fill="', hc, '" opacity="0.65"/>',
            '<ellipse cx="60" cy="24" rx="28" ry="10" fill="', sk, '" opacity="0.35"/>',
            '<line x1="26" y1="30" x2="94" y2="30" stroke="', hc, '" stroke-width="1" opacity="0.4"/>'
        ));
    }
    function _h5(string memory hc) internal view returns (string memory) {
        return string(abi.encodePacked(
            '<ellipse cx="60" cy="27" rx="34" ry="14" fill="', hc, '"/>',
            '<polygon points="30,27 36,3 42,27" fill="', hc, '"/>',
            '<polygon points="43,27 49,0 55,27" fill="', hc, '"/>',
            '<polygon points="57,27 63,0 69,27" fill="', hc, '"/>',
            '<polygon points="71,27 77,3 83,27" fill="', hc, '"/>',
            '<polygon points="84,27 90,6 96,27" fill="', hc, '"/>'
        ));
    }
    function _h6(string memory hc) internal view returns (string memory) {
        return string(abi.encodePacked(
            '<ellipse cx="60" cy="24" rx="36" ry="18" fill="', hc, '"/>',
            '<circle cx="33" cy="18" r="11" fill="', hc, '"/>',
            '<circle cx="46" cy="9" r="13" fill="', hc, '"/>',
            '<circle cx="60" cy="6" r="14" fill="', hc, '"/>',
            '<circle cx="74" cy="9" r="13" fill="', hc, '"/>',
            '<circle cx="87" cy="18" r="11" fill="', hc, '"/>'
        ));
    }
    function _h7(string memory hc) internal view returns (string memory) {
        return string(abi.encodePacked(
            '<ellipse cx="60" cy="21" rx="34" ry="18" fill="', hc, '"/>',
            '<path d="M26,21 Q60,9 94,21" fill="none" stroke="', hc, '" stroke-width="8"/>',
            '<line x1="28" y1="26" x2="92" y2="26" stroke="#ffffff15" stroke-width="1.5"/>',
            '<line x1="30" y1="22" x2="90" y2="22" stroke="#00000012" stroke-width="1"/>'
        ));
    }
    function _h8(string memory hc) internal view returns (string memory) {
        return string(abi.encodePacked(
            '<ellipse cx="60" cy="27" rx="34" ry="12" fill="', hc, '"/>',
            '<circle cx="60" cy="12" r="15" fill="', hc, '"/>',
            '<circle cx="60" cy="12" r="9" fill="', hc, '"/>',
            '<line x1="52" y1="9" x2="68" y2="9" stroke="#00000025" stroke-width="1.5"/>',
            '<circle cx="66" cy="8" r="3" fill="#00000018"/>'
        ));
    }
    function _h9(string memory hc) internal view returns (string memory) {
        return string(abi.encodePacked(
            '<ellipse cx="60" cy="21" rx="34" ry="18" fill="', hc, '"/>',
            '<path d="M26,33 Q23,60 26,87 Q22,99 20,111" stroke="', hc, '" stroke-width="8" fill="none"/>',
            '<path d="M94,33 Q97,60 94,87 Q98,99 100,111" stroke="', hc, '" stroke-width="8" fill="none"/>',
            '<path d="M26,33 Q23,60 26,87" stroke="#00000018" stroke-width="2" stroke-dasharray="5,4" fill="none"/>',
            '<path d="M94,33 Q97,60 94,87" stroke="#00000018" stroke-width="2" stroke-dasharray="5,4" fill="none"/>'
        ));
    }
    function _h10(string memory hc) internal view returns (string memory) {
        return string(abi.encodePacked(
            '<ellipse cx="60" cy="21" rx="34" ry="18" fill="', hc, '"/>',
            '<rect x="26" y="30" width="18" height="18" fill="', hc, '" opacity="0.28"/>',
            '<rect x="76" y="30" width="18" height="18" fill="', hc, '" opacity="0.28"/>',
            '<line x1="26" y1="30" x2="94" y2="30" stroke="#00000020" stroke-width="1.5"/>'
        ));
    }
    function _h11(string memory hc) internal view returns (string memory) {
        return string(abi.encodePacked(
            '<ellipse cx="60" cy="24" rx="28" ry="14" fill="', hc, '"/>',
            '<polygon points="32,27 24,15 38,27" fill="', hc, '"/>',
            '<polygon points="88,27 96,15 82,27" fill="', hc, '"/>',
            '<line x1="32" y1="21" x2="88" y2="21" stroke="#00000018" stroke-width="1"/>'
        ));
    }

    function _u(uint256 v) internal view returns (string memory) {
        if (v == 0) return "0";
        bytes memory buf = new bytes(10);
        uint256 i = 10;
        while (v > 0) { buf[--i] = bytes1(uint8(48 + v % 10)); v /= 10; }
        bytes memory r = new bytes(10 - i);
        for (uint256 j = 0; j < r.length; j++) r[j] = buf[i+j];
        return string(r);
    }
}
