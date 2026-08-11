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

contract NoisiesR3 {
    address public owner;
    constructor() { owner = msg.sender; }

    string[8] private SK = [
        "#e8ddd0","#d8c8b8","#c8a888","#b88868",
        "#986848","#784830","#583820","#381808"
    ];
    string[8] private SKD = [
        "#c8b8a8","#b8a088","#987050","#885030",
        "#683820","#482010","#301808","#180800"
    ];
    string[6] private HC = [
        "#c8a850","#987040","#685030","#382818","#181008","#c0b8b0"
    ];
    string[6] private ACC_C = [
        "#483828","#685038","#303830","#283040","#381828","#584028"
    ];

    function render(NoisieTraits memory t, uint256 seed) external view returns (string memory) {
        return string(abi.encodePacked(
            _glasses(t),
            _acc(t, seed),
            _beardMakeup(t),
            _details(t, seed)
        ));
    }

    // ── GLASSES ───────────────────────────────────────────
    function _glasses(NoisieTraits memory t) internal view returns (string memory) {
        if (t.glasses == 0) return "";
        uint256 gy = 57;
        string memory fc = "none";
        string memory sc = "#381808";
        if (t.glasses == 1) { // wire round
            return string(abi.encodePacked(
                '<circle cx="36" cy="', _u(gy), '" r="11" fill="none" stroke="', sc, '" stroke-width="1.2" opacity="0.8"/>',
                '<circle cx="84" cy="', _u(gy), '" r="11" fill="none" stroke="', sc, '" stroke-width="1.2" opacity="0.8"/>',
                '<line x1="47" y1="', _u(gy), '" x2="73" y2="', _u(gy), '" stroke="', sc, '" stroke-width="1" opacity="0.7"/>',
                '<line x1="16" y1="', _u(gy), '" x2="25" y2="', _u(gy), '" stroke="', sc, '" stroke-width="1" opacity="0.6"/>',
                '<line x1="103" y1="', _u(gy), '" x2="95" y2="', _u(gy), '" stroke="', sc, '" stroke-width="1" opacity="0.6"/>'
            ));
        }
        if (t.glasses == 2) { // thick square
            return string(abi.encodePacked(
                '<rect x="25" y="', _u(gy-8), '" width="22" height="16" rx="2" fill="none" stroke="', sc, '" stroke-width="2.5" opacity="0.85"/>',
                '<rect x="73" y="', _u(gy-8), '" width="22" height="16" rx="2" fill="none" stroke="', sc, '" stroke-width="2.5" opacity="0.85"/>',
                '<line x1="47" y1="', _u(gy), '" x2="73" y2="', _u(gy), '" stroke="', sc, '" stroke-width="2" opacity="0.75"/>',
                '<line x1="14" y1="', _u(gy-2), '" x2="25" y2="', _u(gy-2), '" stroke="', sc, '" stroke-width="1.5" opacity="0.6"/>',
                '<line x1="106" y1="', _u(gy-2), '" x2="95" y2="', _u(gy-2), '" stroke="', sc, '" stroke-width="1.5" opacity="0.6"/>'
            ));
        }
        if (t.glasses == 3) { // thin rectangle
            return string(abi.encodePacked(
                '<rect x="25" y="', _u(gy-5), '" width="22" height="10" rx="1" fill="none" stroke="', sc, '" stroke-width="1" opacity="0.75"/>',
                '<rect x="73" y="', _u(gy-5), '" width="22" height="10" rx="1" fill="none" stroke="', sc, '" stroke-width="1" opacity="0.75"/>',
                '<line x1="47" y1="', _u(gy), '" x2="73" y2="', _u(gy), '" stroke="', sc, '" stroke-width="0.8" opacity="0.6"/>',
                '<line x1="15" y1="', _u(gy), '" x2="25" y2="', _u(gy), '" stroke="', sc, '" stroke-width="0.8" opacity="0.5"/>',
                '<line x1="105" y1="', _u(gy), '" x2="95" y2="', _u(gy), '" stroke="', sc, '" stroke-width="0.8" opacity="0.5"/>'
            ));
        }
        if (t.glasses == 4) { // sunglasses dark
            return string(abi.encodePacked(
                '<ellipse cx="36" cy="', _u(gy), '" rx="12" ry="9" fill="#181008" opacity="0.85"/>',
                '<ellipse cx="84" cy="', _u(gy), '" rx="12" ry="9" fill="#181008" opacity="0.85"/>',
                '<line x1="48" y1="', _u(gy), '" x2="72" y2="', _u(gy), '" stroke="#181008" stroke-width="2" opacity="0.75"/>',
                '<line x1="14" y1="', _u(gy), '" x2="24" y2="', _u(gy), '" stroke="#281808" stroke-width="1.5" opacity="0.6"/>',
                '<line x1="106" y1="', _u(gy), '" x2="96" y2="', _u(gy), '" stroke="#281808" stroke-width="1.5" opacity="0.6"/>',
                '<ellipse cx="32" cy="', _u(gy-3), '" rx="3" ry="2" fill="#ffffff18"/>',
                '<ellipse cx="80" cy="', _u(gy-3), '" rx="3" ry="2" fill="#ffffff18"/>'
            ));
        }
        // colored frame
        string memory col = ACC_C[0];
        return string(abi.encodePacked(
            '<circle cx="36" cy="', _u(gy), '" r="11" fill="none" stroke="', col, '" stroke-width="2" opacity="0.7"/>',
            '<circle cx="84" cy="', _u(gy), '" r="11" fill="none" stroke="', col, '" stroke-width="2" opacity="0.7"/>',
            '<line x1="47" y1="', _u(gy), '" x2="73" y2="', _u(gy), '" stroke="', col, '" stroke-width="1.5" opacity="0.65"/>',
            '<line x1="15" y1="', _u(gy), '" x2="25" y2="', _u(gy), '" stroke="', col, '" stroke-width="1.2" opacity="0.55"/>',
            '<line x1="105" y1="', _u(gy), '" x2="95" y2="', _u(gy), '" stroke="', col, '" stroke-width="1.2" opacity="0.55"/>'
        ));
    }

    // ── ACCESSORIES ───────────────────────────────────────
    function _acc(NoisieTraits memory t, uint256 seed) internal view returns (string memory) {
        uint8 ac = t.acc;
        if (ac == 0) return "";
        string memory hc = HC[t.hairCI];
        string memory ac2 = ACC_C[seed % 6];

        if (ac == 1) { // beanie
            return string(abi.encodePacked(
                '<ellipse cx="60" cy="21" rx="36" ry="18" fill="', hc, '"/>',
                '<rect x="24" y="30" width="72" height="6" fill="', hc, '" opacity="0.8"/>',
                '<line x1="24" y1="36" x2="96" y2="36" stroke="#00000020" stroke-width="1.5"/>',
                '<line x1="30" y1="15" x2="30" y2="36" stroke="#ffffff10" stroke-width="2"/>',
                '<line x1="45" y1="12" x2="45" y2="36" stroke="#ffffff10" stroke-width="2"/>',
                '<line x1="60" y1="9" x2="60" y2="36" stroke="#ffffff10" stroke-width="2"/>',
                '<line x1="75" y1="12" x2="75" y2="36" stroke="#ffffff10" stroke-width="2"/>',
                '<line x1="90" y1="15" x2="90" y2="36" stroke="#ffffff10" stroke-width="2"/>'
            ));
        }
        if (ac == 2) { // cap
            return string(abi.encodePacked(
                '<ellipse cx="60" cy="24" rx="36" ry="18" fill="', hc, '"/>',
                '<rect x="18" y="33" width="84" height="6" rx="2" fill="', hc, '" opacity="0.85"/>',
                '<line x1="18" y1="33" x2="102" y2="33" stroke="#00000020" stroke-width="1"/>',
                '<line x1="60" y1="9" x2="60" y2="33" stroke="#00000015" stroke-width="1.5"/>',
                '<circle cx="60" cy="9" r="4" fill="', hc, '"/>',
                '<circle cx="60" cy="9" r="2" fill="#00000020"/>'
            ));
        }
        if (ac == 3) { // snapback
            return string(abi.encodePacked(
                '<ellipse cx="60" cy="24" rx="36" ry="18" fill="', hc, '"/>',
                '<rect x="21" y="33" width="78" height="5" rx="2" fill="', hc, '"/>',
                '<rect x="21" y="33" width="78" height="2" fill="#00000015" rx="1"/>',
                '<line x1="60" y1="12" x2="60" y2="33" stroke="#00000015" stroke-width="1.5"/>',
                '<rect x="51" y="9" width="18" height="3" rx="1" fill="', hc, '" opacity="0.5"/>'
            ));
        }
        if (ac == 4) { // hoodie
            return string(abi.encodePacked(
                '<ellipse cx="60" cy="21" rx="42" ry="24" fill="', hc, '"/>',
                '<ellipse cx="60" cy="54" rx="30" ry="36" fill="', hc, '" opacity="0.6"/>',
                '<ellipse cx="60" cy="42" rx="18" ry="24" fill="#eae6e0"/>',
                '<line x1="18" y1="18" x2="18" y2="48" stroke="#00000018" stroke-width="1"/>',
                '<line x1="102" y1="18" x2="102" y2="48" stroke="#00000018" stroke-width="1"/>'
            ));
        }
        if (ac == 5) { // stud earrings
            return string(abi.encodePacked(
                '<circle cx="18" cy="60" r="3" fill="#c8a850"/>',
                '<circle cx="102" cy="60" r="3" fill="#c8a850"/>',
                '<circle cx="18" cy="60" r="1.5" fill="#f0e8c8"/>',
                '<circle cx="102" cy="60" r="1.5" fill="#f0e8c8"/>'
            ));
        }
        if (ac == 6) { // hoop earrings
            return string(abi.encodePacked(
                '<circle cx="18" cy="66" r="8" fill="none" stroke="#c8a850" stroke-width="2" opacity="0.85"/>',
                '<circle cx="102" cy="66" r="8" fill="none" stroke="#c8a850" stroke-width="2" opacity="0.85"/>'
            ));
        }
        if (ac == 7) { // chain necklace
            return string(abi.encodePacked(
                '<path d="M42,96 Q60,105 78,96" stroke="#c8a850" stroke-width="1.5" fill="none" opacity="0.8"/>',
                '<path d="M42,96 Q60,105 78,96" stroke="#f0e8c8" stroke-width="0.5" fill="none" opacity="0.5" stroke-dasharray="3,4"/>',
                '<circle cx="60" cy="105" r="3" fill="#c8a850" opacity="0.8"/>',
                '<circle cx="60" cy="105" r="1.5" fill="#f0e8c8" opacity="0.7"/>'
            ));
        }
        if (ac == 8) { // surgical mask
            return string(abi.encodePacked(
                '<rect x="21" y="72" width="78" height="36" rx="6" fill="#f0ece6" opacity="0.92"/>',
                '<line x1="21" y1="82" x2="99" y2="82" stroke="#d8d0c8" stroke-width="0.8" opacity="0.6"/>',
                '<line x1="21" y1="92" x2="99" y2="92" stroke="#d8d0c8" stroke-width="0.8" opacity="0.6"/>',
                '<path d="M21,75 Q15,75 15,81 L15,96 Q15,102 21,102" stroke="#d8d0c8" stroke-width="1" fill="none" opacity="0.5"/>',
                '<path d="M99,75 Q105,75 105,81 L105,96 Q105,102 99,102" stroke="#d8d0c8" stroke-width="1" fill="none" opacity="0.5"/>'
            ));
        }
        if (ac == 9) { // headphones
            return string(abi.encodePacked(
                '<path d="M21,54 Q21,18 60,18 Q99,18 99,54" stroke="#383028" stroke-width="4" fill="none" opacity="0.85"/>',
                '<rect x="12" y="48" width="12" height="18" rx="4" fill="#383028" opacity="0.85"/>',
                '<rect x="96" y="48" width="12" height="18" rx="4" fill="#383028" opacity="0.85"/>',
                '<rect x="14" y="51" width="8" height="12" rx="3" fill="#585048" opacity="0.6"/>'
            ));
        }
        if (ac == 10) { // bandana on forehead
            return string(abi.encodePacked(
                '<rect x="24" y="27" width="72" height="12" rx="3" fill="', ac2, '"/>',
                '<line x1="24" y1="33" x2="96" y2="33" stroke="#ffffff18" stroke-width="1.5"/>',
                '<line x1="24" y1="36" x2="96" y2="36" stroke="#00000015" stroke-width="1"/>',
                '<circle cx="96" cy="27" r="3" fill="', ac2, '"/>',
                '<circle cx="24" cy="27" r="3" fill="', ac2, '"/>'
            ));
        }
        if (ac == 11) { // crown
            return string(abi.encodePacked(
                '<polygon points="30,36 36,15 42,36" fill="#c8a820"/>',
                '<polygon points="42,36 50,9 58,36" fill="#c8a820"/>',
                '<polygon points="56,36 60,3 64,36" fill="#d8b830"/>',
                '<polygon points="62,36 70,9 78,36" fill="#c8a820"/>',
                '<polygon points="78,36 84,15 90,36" fill="#c8a820"/>',
                '<rect x="30" y="33" width="60" height="6" rx="2" fill="#c8a820"/>',
                '<circle cx="60" cy="6" r="4" fill="#c83820"/>',
                '<circle cx="50" cy="12" r="3" fill="#2040c8"/>',
                '<circle cx="70" cy="12" r="3" fill="#2040c8"/>',
                '<line x1="30" y1="33" x2="90" y2="33" stroke="#a88818" stroke-width="1"/>'
            ));
        }
        if (ac == 12) { // scarf
            return string(abi.encodePacked(
                '<rect x="27" y="90" width="66" height="15" rx="4" fill="', ac2, '"/>',
                '<rect x="27" y="90" width="66" height="5" rx="2" fill="', ac2, '" opacity="0.6"/>',
                '<line x1="27" y1="96" x2="93" y2="96" stroke="#ffffff18" stroke-width="1.5"/>',
                '<rect x="57" y="90" width="18" height="24" rx="3" fill="', ac2, '"/>',
                '<line x1="60" y1="90" x2="60" y2="114" stroke="#00000018" stroke-width="1"/>'
            ));
        }
        // turtleneck (ac == 13)
        return string(abi.encodePacked(
            '<rect x="33" y="84" width="54" height="30" rx="4" fill="', acc_clothingColor(t), '"/>',
            '<line x1="33" y1="90" x2="87" y2="90" stroke="#ffffff15" stroke-width="1.5"/>',
            '<line x1="33" y1="96" x2="87" y2="96" stroke="#00000010" stroke-width="1"/>',
            '<ellipse cx="60" cy="84" rx="21" ry="6" fill="', acc_clothingColor(t), '"/>'
        ));
    }

    function acc_clothingColor(NoisieTraits memory t) internal view returns (string memory) {
        return ACC_C[uint8(uint256(keccak256(abi.encodePacked(t.skinIdx, t.hairCI))) % 6)];
    }

    // ── BEARD / MAKEUP ────────────────────────────────────
    function _beardMakeup(NoisieTraits memory t) internal view returns (string memory) {
        string memory sk = SK[t.skinIdx];
        string memory skd = SKD[t.skinIdx];
        string memory hc = HC[t.hairCI];
        if (t.gender == 0 && t.beard > 0) {
            uint8 bd = t.beard;
            if (bd == 1) { // shadow
                return string(abi.encodePacked(
                    '<ellipse cx="60" cy="87" rx="27" ry="15" fill="', hc, '" opacity="0.12"/>',
                    '<ellipse cx="60" cy="78" rx="21" ry="9" fill="', hc, '" opacity="0.08"/>'
                ));
            }
            if (bd == 2) { // stubble
                return string(abi.encodePacked(
                    '<ellipse cx="60" cy="87" rx="27" ry="15" fill="', hc, '" opacity="0.22"/>',
                    '<ellipse cx="60" cy="78" rx="21" ry="9" fill="', hc, '" opacity="0.15"/>'
                ));
            }
            if (bd == 3) { // goatee
                return string(abi.encodePacked(
                    '<ellipse cx="60" cy="90" rx="15" ry="12" fill="', hc, '" opacity="0.75"/>',
                    '<path d="M45,87 Q60,81 75,87" stroke="', hc, '" stroke-width="4" fill="none" opacity="0.5"/>'
                ));
            }
            if (bd == 4) { // full beard
                return string(abi.encodePacked(
                    '<ellipse cx="60" cy="87" rx="30" ry="18" fill="', hc, '" opacity="0.8"/>',
                    '<path d="M30,81 Q60,72 90,81" stroke="', hc, '" stroke-width="5" fill="none" opacity="0.7"/>',
                    '<ellipse cx="60" cy="87" rx="24" ry="12" fill="', hc, '" opacity="0.3"/>',
                    '<line x1="48" y1="81" x2="45" y2="99" stroke="#00000015" stroke-width="1"/>',
                    '<line x1="60" y1="78" x2="60" y2="99" stroke="#00000015" stroke-width="1"/>',
                    '<line x1="72" y1="81" x2="75" y2="99" stroke="#00000015" stroke-width="1"/>'
                ));
            }
            // mustache (bd == 5)
            return string(abi.encodePacked(
                '<path d="M42,81 Q51,75 60,78 Q69,75 78,81" stroke="', hc, '" stroke-width="5" fill="none" opacity="0.75" stroke-linecap="round"/>',
                '<path d="M42,81 Q51,75 60,78 Q69,75 78,81" stroke="#ffffff18" stroke-width="1" fill="none"/>'
            ));
        }
        if (t.gender == 1 && t.makeup >= 4) { // full glam contour
            return string(abi.encodePacked(
                '<ellipse cx="27" cy="66" rx="9" ry="15" fill="', skd, '" opacity="0.2"/>',
                '<ellipse cx="93" cy="66" rx="9" ry="15" fill="', skd, '" opacity="0.2"/>',
                '<ellipse cx="60" cy="42" rx="12" ry="6" fill="#ffffff15"/>',
                '<ellipse cx="30" cy="75" rx="9" ry="6" fill="#f09050" opacity="0.18"/>',
                '<ellipse cx="90" cy="75" rx="9" ry="6" fill="#f09050" opacity="0.18"/>'
            ));
        }
        return "";
    }

    // ── FACE DETAILS ──────────────────────────────────────
    function _details(NoisieTraits memory t, uint256 seed) internal view returns (string memory) {
        string memory skd = SKD[t.skinIdx];
        string memory out = "";

        // Freckles
        if (t.freckles > 0) {
            uint256 fc = t.freckles == 2 ? 16 : 7;
            uint256[16] memory fxA = [uint256(33),39,45,51,57,63,69,75,36,42,48,54,60,66,72,78];
            uint256[16] memory fyA = [uint256(48),51,48,51,48,51,48,51,54,57,54,57,54,57,54,57];
            for (uint256 i = 0; i < fc; i++) {
                uint256 fx = fxA[i] + ((seed >> (i*2)) % 5);
                uint256 fy = fyA[i] + ((seed >> (i*3)) % 4);
                out = string(abi.encodePacked(out, '<circle cx="', _u(fx), '" cy="', _u(fy), '" r="1.2" fill="', skd, '" opacity="0.55"/>'));
            }
        }

        // Dimples
        if (t.dimples > 0) {
            string memory op = t.dimples == 2 ? "0.35" : "0.2";
            out = string(abi.encodePacked(out,
                '<circle cx="42" cy="84" r="3" fill="', skd, '" opacity="', op, '"/>',
                '<circle cx="78" cy="84" r="3" fill="', skd, '" opacity="', op, '"/>'
            ));
        }

        // Mole
        if (t.mole > 0) {
            uint256[5] memory mx = [uint256(36),84,66,42,60];
            uint256[5] memory my = [uint256(72),72,78,51,42];
            out = string(abi.encodePacked(out,
                '<circle cx="', _u(mx[t.mole-1]), '" cy="', _u(my[t.mole-1]), '" r="2.5" fill="', skd, '" opacity="0.7"/>',
                '<circle cx="', _u(mx[t.mole-1]+1), '" cy="', _u(my[t.mole-1]-1), '" r="0.8" fill="#ffffff30"/>'
            ));
        }

        // Scar
        if (t.scar > 0) {
            if (t.scar == 1) {
                out = string(abi.encodePacked(out, '<line x1="36" y1="51" x2="42" y2="63" stroke="', skd, '" stroke-width="1.5" opacity="0.5"/>'));
            } else if (t.scar == 2) {
                out = string(abi.encodePacked(out, '<line x1="42" y1="45" x2="51" y2="66" stroke="', skd, '" stroke-width="1.5" opacity="0.45"/>'));
            } else {
                out = string(abi.encodePacked(out, '<line x1="57" y1="90" x2="63" y2="96" stroke="', skd, '" stroke-width="1.5" opacity="0.5"/>'));
            }
        }

        // Age lines
        if (t.age == 3) {
            out = string(abi.encodePacked(out,
                '<path d="M24,57 Q27,63 24,66" stroke="', skd, '" stroke-width="1" fill="none" opacity="0.3"/>',
                '<path d="M96,57 Q93,63 96,66" stroke="', skd, '" stroke-width="1" fill="none" opacity="0.3"/>',
                '<line x1="39" y1="39" x2="51" y2="39" stroke="', skd, '" stroke-width="0.8" opacity="0.25"/>',
                '<line x1="69" y1="39" x2="81" y2="39" stroke="', skd, '" stroke-width="0.8" opacity="0.25"/>',
                '<path d="M39,72 Q36,81 39,87" stroke="', skd, '" stroke-width="0.8" fill="none" opacity="0.25"/>',
                '<path d="M81,72 Q84,81 81,87" stroke="', skd, '" stroke-width="0.8" fill="none" opacity="0.25"/>'
            ));
        } else if (t.age == 2) {
            out = string(abi.encodePacked(out,
                '<path d="M39,72 Q36,81 39,84" stroke="', skd, '" stroke-width="0.8" fill="none" opacity="0.2"/>',
                '<path d="M81,72 Q84,81 81,84" stroke="', skd, '" stroke-width="0.8" fill="none" opacity="0.2"/>'
            ));
        }

        // Cheek blush contour
        out = string(abi.encodePacked(out,
            '<ellipse cx="33" cy="69" rx="10" ry="12" fill="', skd, '" opacity="0.08"/>',
            '<ellipse cx="87" cy="69" rx="10" ry="12" fill="', skd, '" opacity="0.08"/>'
        ));

        return out;
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
