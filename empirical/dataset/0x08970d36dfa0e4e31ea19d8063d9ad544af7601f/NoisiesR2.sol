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

contract NoisiesR2 {
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
    string[8] private SKH = [
        "#fff8f0","#f8ece0","#e8c8a0","#d8a870",
        "#b88050","#986040","#784830","#502818"
    ];
    string[6] private HC = [
        "#c8a850","#987040","#685030","#382818","#181008","#c0b8b0"
    ];

    function render(NoisieTraits memory t) external view returns (string memory) {
        return string(abi.encodePacked(_brows(t), _eyes(t), _nose(t), _lips(t)));
    }

    // ── EYEBROWS ──────────────────────────────────────────
    function _brows(NoisieTraits memory t) internal view returns (string memory) {
        string memory hc = HC[t.hairCI];
        uint256 by = t.gender == 1 ? 42 : 45;
        uint256 bh = t.browStyle == 2 || t.browStyle == 5 ? 4 : 3;
        // expression affects brow position/angle
        if (t.expr == 2) { // serious - inner down
            return string(abi.encodePacked(
                '<path d="M30,', _u(by+2), ' L51,', _u(by), '" stroke="', hc, '" stroke-width="', _u(bh), '" stroke-linecap="round"/>',
                '<path d="M69,', _u(by), ' L90,', _u(by+2), '" stroke="', hc, '" stroke-width="', _u(bh), '" stroke-linecap="round"/>'
            ));
        }
        if (t.expr == 3) { // surprise - raised + arch
            by = t.gender == 1 ? 36 : 39;
            return string(abi.encodePacked(
                '<path d="M30,', _u(by+3), ' Q40,', _u(by-2), ' 51,', _u(by+1), '" stroke="', hc, '" stroke-width="', _u(bh), '" fill="none" stroke-linecap="round"/>',
                '<path d="M69,', _u(by+1), ' Q80,', _u(by-2), ' 90,', _u(by+3), '" stroke="', hc, '" stroke-width="', _u(bh), '" fill="none" stroke-linecap="round"/>'
            ));
        }
        if (t.browStyle == 0) { // natural arch
            return string(abi.encodePacked(
                '<path d="M30,', _u(by+1), ' Q40,', _u(by-2), ' 51,', _u(by), '" stroke="', hc, '" stroke-width="', _u(bh), '" fill="none" stroke-linecap="round"/>',
                '<path d="M69,', _u(by), ' Q80,', _u(by-2), ' 90,', _u(by+1), '" stroke="', hc, '" stroke-width="', _u(bh), '" fill="none" stroke-linecap="round"/>'
            ));
        }
        if (t.browStyle == 1) { // thin arched
            return string(abi.encodePacked(
                '<path d="M33,', _u(by), ' Q41,', _u(by-3), ' 50,', _u(by), '" stroke="', hc, '" stroke-width="2" fill="none" stroke-linecap="round"/>',
                '<path d="M70,', _u(by), ' Q79,', _u(by-3), ' 87,', _u(by), '" stroke="', hc, '" stroke-width="2" fill="none" stroke-linecap="round"/>'
            ));
        }
        if (t.browStyle == 2) { // thick straight
            return string(abi.encodePacked(
                '<rect x="30" y="', _u(by), '" width="21" height="4" rx="1" fill="', hc, '"/>',
                '<rect x="69" y="', _u(by), '" width="21" height="4" rx="1" fill="', hc, '"/>'
            ));
        }
        if (t.browStyle == 3) { // defined
            return string(abi.encodePacked(
                '<path d="M30,', _u(by+2), ' Q38,', _u(by-3), ' 51,', _u(by), '" stroke="', hc, '" stroke-width="3" fill="none" stroke-linecap="round"/>',
                '<path d="M69,', _u(by), ' Q82,', _u(by-3), ' 90,', _u(by+2), '" stroke="', hc, '" stroke-width="3" fill="none" stroke-linecap="round"/>',
                '<path d="M30,', _u(by+2), ' Q38,', _u(by-3), ' 51,', _u(by), '" stroke="', hc, '" stroke-width="1" fill="none" stroke-linecap="round" opacity="0.4"/>'
            ));
        }
        if (t.browStyle == 4) { // sparse
            return string(abi.encodePacked(
                '<path d="M32,', _u(by), ' Q40,', _u(by-2), ' 50,', _u(by), '" stroke="', hc, '" stroke-width="1.5" fill="none" stroke-linecap="round" stroke-dasharray="3,2"/>',
                '<path d="M70,', _u(by), ' Q80,', _u(by-2), ' 88,', _u(by), '" stroke="', hc, '" stroke-width="1.5" fill="none" stroke-linecap="round" stroke-dasharray="3,2"/>'
            ));
        }
        // bushy
        return string(abi.encodePacked(
            '<path d="M28,', _u(by+2), ' Q39,', _u(by-3), ' 52,', _u(by+1), '" stroke="', hc, '" stroke-width="5" fill="none" stroke-linecap="round"/>',
            '<path d="M68,', _u(by+1), ' Q81,', _u(by-3), ' 92,', _u(by+2), '" stroke="', hc, '" stroke-width="5" fill="none" stroke-linecap="round"/>',
            '<path d="M28,', _u(by+2), ' Q39,', _u(by-3), ' 52,', _u(by+1), '" stroke="#ffffff18" stroke-width="1" fill="none"/>'
        ));
    }

    // ── EYES ──────────────────────────────────────────────
    function _eyes(NoisieTraits memory t) internal view returns (string memory) {
        uint256 ey = 57;
        uint256[3] memory erx = [uint256(9), 11, 13];
        uint256[3] memory ery = [uint256(6), 7, 9];
        uint256 rx = erx[t.eyeSize];
        uint256 ry2 = ery[t.eyeSize];
        string memory sk = SK[t.skinIdx];
        string memory skd = SKD[t.skinIdx];

        string memory le = _drawEye(t, 36, ey, rx, ry2, sk, skd, false);
        string memory re = _drawEye(t, 84, ey, rx, ry2, sk, skd, true);
        return string(abi.encodePacked(le, re));
    }

    function _drawEye(NoisieTraits memory t, uint256 cx, uint256 cy, uint256 rx, uint256 ry2, string memory sk, string memory skd, bool isRight) internal view returns (string memory) {
        // Eye socket shadow
        string memory socket = string(abi.encodePacked(
            '<ellipse cx="', _u(cx), '" cy="', _u(cy), '" rx="', _u(rx+2), '" ry="', _u(ry2+3), '" fill="#00000010"/>'
        ));
        // Eye white
        string memory white;
        if (t.eyeStyle == 0) { // round
            white = string(abi.encodePacked('<ellipse cx="', _u(cx), '" cy="', _u(cy), '" rx="', _u(rx), '" ry="', _u(ry2), '" fill="#f8f5f0"/>'));
        } else if (t.eyeStyle == 1) { // almond
            white = string(abi.encodePacked('<ellipse cx="', _u(cx), '" cy="', _u(cy), '" rx="', _u(rx), '" ry="', _u(ry2-1), '" fill="#f8f5f0"/>'));
        } else if (t.eyeStyle == 2) { // hooded
            white = string(abi.encodePacked(
                '<ellipse cx="', _u(cx), '" cy="', _u(cy+1), '" rx="', _u(rx), '" ry="', _u(ry2-1), '" fill="#f8f5f0"/>',
                '<rect x="', _u(cx-rx), '" y="', _u(cy-ry2), '" width="', _u(rx*2), '" height="', _u(ry2/2+1), '" fill="', sk, '"/>'
            ));
        } else if (t.eyeStyle == 3) { // wide
            white = string(abi.encodePacked('<ellipse cx="', _u(cx), '" cy="', _u(cy), '" rx="', _u(rx+2), '" ry="', _u(ry2+1), '" fill="#f8f5f0"/>'));
        } else if (t.eyeStyle == 4) { // narrow
            white = string(abi.encodePacked('<ellipse cx="', _u(cx), '" cy="', _u(cy+1), '" rx="', _u(rx), '" ry="', _u(ry2-2), '" fill="#f8f5f0"/>'));
        } else if (t.eyeStyle == 5) { // upturned
            uint256 ox = isRight ? cx-2 : cx+2;
            white = string(abi.encodePacked('<ellipse cx="', _u(ox), '" cy="', _u(cy), '" rx="', _u(rx), '" ry="', _u(ry2), '" fill="#f8f5f0"/>'));
        } else if (t.eyeStyle == 6) { // downturned
            uint256 ox2 = isRight ? cx+2 : cx-2;
            white = string(abi.encodePacked('<ellipse cx="', _u(ox2), '" cy="', _u(cy), '" rx="', _u(rx), '" ry="', _u(ry2), '" fill="#f8f5f0"/>'));
        } else { // monolid
            white = string(abi.encodePacked('<ellipse cx="', _u(cx), '" cy="', _u(cy+1), '" rx="', _u(rx), '" ry="', _u(ry2-2), '" fill="#f8f5f0"/>'));
        }
        // Iris
        uint256 ir = ry2 > 6 ? 5 : ry2 - 1;
        string memory iris = string(abi.encodePacked(
            '<circle cx="', _u(cx), '" cy="', _u(cy), '" r="', _u(ir), '" fill="#483828"/>',
            '<circle cx="', _u(cx), '" cy="', _u(cy), '" r="', _u(ir*3/5), '" fill="#181008"/>',
            '<circle cx="', _u(cx-ir/3), '" cy="', _u(cy-ir/3), '" r="', _u(ir/4+1), '" fill="#f0e8e0" opacity="0.9"/>'
        ));
        // Lashes
        string memory lash = string(abi.encodePacked(
            '<path d="M', _u(cx-rx), ',', _u(cy-ry2+1), ' Q', _u(cx), ',', _u(cy-ry2-3), ' ', _u(cx+rx), ',', _u(cy-ry2+1), '" stroke="#181008" stroke-width="', t.gender==1 || t.makeup>=3 ? "2.5" : "2", '" fill="none" stroke-linecap="round"/>',
            '<path d="M', _u(cx-rx), ',', _u(cy+ry2-1), ' Q', _u(cx), ',', _u(cy+ry2+1), ' ', _u(cx+rx), ',', _u(cy+ry2-1), '" stroke="#48382880" stroke-width="1" fill="none"/>'
        ));
        // Expression mods
        string memory exprMod = "";
        if (t.expr == 4) { // tired - drooping lid
            exprMod = string(abi.encodePacked('<rect x="', _u(cx-rx), '" y="', _u(cy-ry2), '" width="', _u(rx*2), '" height="', _u(ry2/2+2), '" fill="', sk, '" opacity="0.6"/>'));
        }
        if (t.makeup >= 1 && t.gender == 1) { // eyeshadow
            exprMod = string(abi.encodePacked(exprMod, '<ellipse cx="', _u(cx), '" cy="', _u(cy-ry2/2), '" rx="', _u(rx), '" ry="3" fill="#907060" opacity="0.3"/>'));
        }
        if (t.makeup >= 2 && t.gender == 1) { // liner
            exprMod = string(abi.encodePacked(exprMod, '<path d="M', _u(cx-rx-2), ',', _u(cy-ry2+2), ' Q', _u(cx), ',', _u(cy-ry2-4), ' ', _u(cx+rx+2), ',', _u(cy-ry2+2), '" stroke="#181008" stroke-width="1.5" fill="none"/>'));
        }
        return string(abi.encodePacked(socket, white, iris, lash, exprMod));
    }

    // ── NOSE ──────────────────────────────────────────────
    function _nose(NoisieTraits memory t) internal view returns (string memory) {
        string memory skd = SKD[t.skinIdx];
        uint256 ns = t.noseStyle;
        if (ns == 0) { // button
            return string(abi.encodePacked(
                '<ellipse cx="60" cy="78" rx="7" ry="5" fill="', skd, '" opacity="0.5"/>',
                '<circle cx="54" cy="79" r="3" fill="', skd, '" opacity="0.6"/>',
                '<circle cx="66" cy="79" r="3" fill="', skd, '" opacity="0.6"/>',
                '<ellipse cx="60" cy="75" rx="3" ry="2" fill="#ffffff20"/>'
            ));
        }
        if (ns == 1) { // straight narrow
            return string(abi.encodePacked(
                '<line x1="60" y1="66" x2="60" y2="78" stroke="', skd, '" stroke-width="1.5" opacity="0.5"/>',
                '<ellipse cx="60" cy="79" rx="6" ry="4" fill="', skd, '" opacity="0.45"/>',
                '<circle cx="55" cy="79" r="2.5" fill="', skd, '" opacity="0.5"/>',
                '<circle cx="65" cy="79" r="2.5" fill="', skd, '" opacity="0.5"/>',
                '<ellipse cx="60" cy="74" rx="2" ry="2" fill="#ffffff18"/>'
            ));
        }
        if (ns == 2) { // wide
            return string(abi.encodePacked(
                '<ellipse cx="60" cy="78" rx="10" ry="5" fill="', skd, '" opacity="0.5"/>',
                '<circle cx="51" cy="79" r="4" fill="', skd, '" opacity="0.55"/>',
                '<circle cx="69" cy="79" r="4" fill="', skd, '" opacity="0.55"/>',
                '<ellipse cx="60" cy="75" rx="4" ry="2" fill="#ffffff18"/>'
            ));
        }
        if (ns == 3) { // upturned
            return string(abi.encodePacked(
                '<ellipse cx="60" cy="80" rx="7" ry="4" fill="', skd, '" opacity="0.5"/>',
                '<circle cx="54" cy="80" r="3" fill="', skd, '" opacity="0.6"/>',
                '<circle cx="66" cy="80" r="3" fill="', skd, '" opacity="0.6"/>',
                '<path d="M53,76 Q60,72 67,76" stroke="', skd, '" stroke-width="1" fill="none" opacity="0.4"/>',
                '<ellipse cx="60" cy="74" rx="2" ry="1.5" fill="#ffffff20"/>'
            ));
        }
        // aquiline
        return string(abi.encodePacked(
            '<path d="M60,63 Q58,72 60,78 Q57,80 55,82" stroke="', skd, '" stroke-width="1.5" fill="none" opacity="0.5"/>',
            '<path d="M60,63 Q62,72 60,78 Q63,80 65,82" stroke="', skd, '" stroke-width="1.5" fill="none" opacity="0.5"/>',
            '<ellipse cx="60" cy="78" rx="6" ry="4" fill="', skd, '" opacity="0.35"/>',
            '<ellipse cx="60" cy="66" rx="2" ry="2" fill="#ffffff15"/>'
        ));
    }

    // ── LIPS ──────────────────────────────────────────────
    function _lips(NoisieTraits memory t) internal view returns (string memory) {
        string memory skd = SKD[t.skinIdx];
        string memory skh = SKH[t.skinIdx];
        uint256 ls = t.lipStyle;
        uint256 lw = t.lipFull == 2 ? 14 : t.lipFull == 1 ? 12 : 10;
        uint256 lh = t.lipFull == 2 ? 5 : t.lipFull == 1 ? 4 : 3;

        string memory base;
        if (ls == 0) { // thin
            base = string(abi.encodePacked(
                '<path d="M', _u(60-lw), ',87 Q60,84 ', _u(60+lw), ',87" stroke="', skd, '" stroke-width="2.5" fill="none" stroke-linecap="round"/>',
                '<ellipse cx="60" cy="', _u(87+lh), '" rx="', _u(lw-1), '" ry="', _u(lh), '" fill="', skd, '" opacity="0.7"/>'
            ));
        } else if (ls == 1) { // cupid bow
            base = string(abi.encodePacked(
                '<path d="M', _u(60-lw), ',87 Q', _u(60-lw/2), ',84 60,86 Q', _u(60+lw/2), ',84 ', _u(60+lw), ',87" stroke="', skd, '" stroke-width="2.5" fill="none" stroke-linecap="round"/>',
                '<ellipse cx="60" cy="', _u(87+lh+1), '" rx="', _u(lw), '" ry="', _u(lh+1), '" fill="', skd, '" opacity="0.75"/>'
            ));
        } else if (ls == 2) { // full
            base = string(abi.encodePacked(
                '<path d="M', _u(60-lw), ',87 Q', _u(60-lw/2), ',83 60,85 Q', _u(60+lw/2), ',83 ', _u(60+lw), ',87" stroke="', skd, '" stroke-width="3" fill="none" stroke-linecap="round"/>',
                '<ellipse cx="60" cy="', _u(88+lh), '" rx="', _u(lw+1), '" ry="', _u(lh+2), '" fill="', skd, '" opacity="0.8"/>'
            ));
        } else if (ls == 3) { // wide
            base = string(abi.encodePacked(
                '<path d="M', _u(60-lw-2), ',87 Q60,84 ', _u(60+lw+2), ',87" stroke="', skd, '" stroke-width="2.5" fill="none" stroke-linecap="round"/>',
                '<ellipse cx="60" cy="', _u(87+lh), '" rx="', _u(lw+2), '" ry="', _u(lh), '" fill="', skd, '" opacity="0.7"/>'
            ));
        } else { // small
            lw = lw > 4 ? lw - 4 : 6;
            base = string(abi.encodePacked(
                '<path d="M', _u(60-lw), ',87 Q60,85 ', _u(60+lw), ',87" stroke="', skd, '" stroke-width="2" fill="none" stroke-linecap="round"/>',
                '<ellipse cx="60" cy="', _u(87+lh), '" rx="', _u(lw-1), '" ry="', _u(lh), '" fill="', skd, '" opacity="0.65"/>'
            ));
        }

        // Expression modifiers
        string memory exMod = "";
        if (t.expr == 1) { // smile - corners up
            exMod = string(abi.encodePacked(
                '<circle cx="', _u(60-lw-1), '" cy="87" r="2" fill="', skd, '" opacity="0.5"/>',
                '<circle cx="', _u(60+lw+1), '" cy="87" r="2" fill="', skd, '" opacity="0.5"/>'
            ));
        } else if (t.expr == 3) { // open mouth
            exMod = string(abi.encodePacked(
                '<ellipse cx="60" cy="90" rx="8" ry="5" fill="#281808" opacity="0.8"/>',
                '<ellipse cx="60" cy="88" rx="6" ry="2" fill="#f0e0d0" opacity="0.7"/>'
            ));
        } else if (t.expr == 4) { // smirk
            exMod = string(abi.encodePacked('<line x1="', _u(60+lw-2), '" y1="87" x2="', _u(60+lw+3), '" y2="90" stroke="', skd, '" stroke-width="1.5" opacity="0.5"/>'));
        }

        // Lip highlight
        string memory highlight = string(abi.encodePacked('<ellipse cx="60" cy="', _u(88+lh/2), '" rx="', _u(lw/2), '" ry="1.5" fill="', skh, '" opacity="0.5"/>'));

        // Bold lip makeup
        if (t.makeup >= 3 && t.gender == 1) {
            return string(abi.encodePacked(base, exMod, highlight,
                '<ellipse cx="60" cy="', _u(87+lh), '" rx="', _u(lw), '" ry="', _u(lh+1), '" fill="#783828" opacity="0.4"/>'
            ));
        }

        return string(abi.encodePacked(base, exMod, highlight));
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
