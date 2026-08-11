// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibString} from "./src/utils/LibString.sol";

/// @notice Low-level SVG primitive library for `mirror`.
/// @dev Deployed separately so MirrorRenderer stays under 24 KB.
///      All functions are `external pure` — MirrorRenderer calls them via DELEGATECALL
///      using the `Parts` library pattern, or simply as external calls.
contract MirrorRendererParts {
    using LibString for uint256;

    // -----------------------------------------------------------------------
    // Palettes
    // -----------------------------------------------------------------------

    function pal(uint256 i) external pure returns (string memory a, string memory l) {
        string[28] memory P = [
            "e2e8f0","94a3b8", "f43f5e","fda4af", "22d3ee","67e8f9",
            "a855f7","d8b4fe", "eab308","fde047", "10b981","6ee7b7",
            "fb923c","fed7aa", "ec4899","fbcfe8", "38bdf8","7dd3fc",
            "84cc16","bef264", "f87171","fecaca", "2dd4bf","99f6e4",
            "c084fc","e9d5ff", "fbbf24","fef08a"
        ];
        return (P[i * 2], P[i * 2 + 1]);
    }

    // -----------------------------------------------------------------------
    // Weighted picker
    // -----------------------------------------------------------------------

    function weighted(uint256 s, uint256 shift, bytes memory w) external pure returns (uint256) {
        uint256 total;
        for (uint256 i; i < w.length; ++i) total += uint8(w[i]);
        uint256 r = (s >> shift) % total;
        uint256 acc;
        for (uint256 i; i < w.length; ++i) {
            acc += uint8(w[i]);
            if (r < acc) return i;
        }
        return w.length - 1;
    }

    // -----------------------------------------------------------------------
    // Face shape
    // -----------------------------------------------------------------------

    function face(uint256 t) external pure returns (string memory path, uint256 rx, uint256 ry, uint256 top) {
        if (t==0) return ("M150 55 A72 85 0 0 0 150 225",72,85,55);
        if (t==1) return ("M150 48 A60 95 0 0 0 150 232",60,95,48);
        if (t==2) return ("M150 58 L98 78 L84 150 L102 205 L150 224",0,0,58);
        if (t==3) return ("M150 62 A82 78 0 0 0 150 218",82,78,62);
        if (t==4) return ("M150 52 L92 92 L94 162 L150 226",0,0,52);
        if (t==5) return ("M150 56 L100 70 L86 130 L96 195 L150 220",0,0,56);
        if (t==6) return ("M150 60 A68 80 0 0 0 150 220",68,80,60);
        return ("M150 50 L108 75 L88 145 L110 210 L150 226",0,0,50);
    }

    // -----------------------------------------------------------------------
    // Seam
    // -----------------------------------------------------------------------

    function seam(uint256 t, string memory c) external pure returns (string memory) {
        if (t==0) return string.concat('<path d="M150 56 L147 100 L153 140 L148 180 L150 224" stroke="#',c,'" stroke-width="1.5" fill="none" filter="url(#g)" opacity=".85"/>');
        if (t==1) return string.concat('<path d="M150 56 Q140 90 150 120 Q160 150 150 180 Q142 210 150 224" stroke="#',c,'" stroke-width="1.5" fill="none" filter="url(#g)" opacity=".85"/>');
        if (t==2) return string.concat('<path d="M150 56 L142 85 L156 110 L144 140 L156 170 L146 200 L150 224" stroke="#',c,'" stroke-width="1.5" fill="none" filter="url(#g)" opacity=".85"/>');
        if (t==3) return string.concat('<line x1="150" y1="56" x2="150" y2="224" stroke="#',c,'" stroke-width="2" filter="url(#g)" opacity=".8"/>');
        if (t==4) return string.concat('<path d="M150 56 L138 110 L158 120 L140 224" stroke="#',c,'" stroke-width="1.5" fill="none" filter="url(#g)" opacity=".9"/>');
        if (t==5) return string.concat('<path d="M150 56 L150 90 M150 105 L150 135 M150 150 L150 180 M150 195 L150 224" stroke="#',c,'" stroke-width="2" filter="url(#g)" opacity=".8"/>');
        return string.concat('<path d="M150 56 C158 95 142 125 150 140 C158 155 142 185 150 224" stroke="#',c,'" stroke-width="1.5" fill="none" filter="url(#g)" opacity=".85"/>');
    }

    // -----------------------------------------------------------------------
    // Eye
    // -----------------------------------------------------------------------

    function eye(uint256 t, uint256 x, string memory c, bool left) external pure returns (string memory) {
        string memory xs = x.toString();
        if (t==0) return string.concat('<circle cx="',xs,'" cy="125" r="7" fill="#',c,'"/>');
        if (t==2) return string.concat('<rect x="',(x-8).toString(),'" y="122" width="16" height="6" fill="#',c,'"/>');
        if (t==3) return string.concat('<rect x="',(x-3).toString(),'" y="117" width="6" height="16" fill="#',c,'"/>');
        if (t==4) return string.concat('<g stroke="#',c,'" stroke-width="2.5"><path d="M',(x-6).toString(),' 119 L',(x+6).toString(),' 131 M',(x+6).toString(),' 119 L',(x-6).toString(),' 131"/></g>');
        if (t==5) return string.concat('<circle cx="',xs,'" cy="125" r="7" fill="none" stroke="#',c,'" stroke-width="2.5"/>');
        if (t==6) return string.concat('<path d="M',(x-8).toString(),' 125 Q',xs,' 116 ',(x+8).toString(),' 125 Q',xs,' 134 ',(x-8).toString(),' 125Z" fill="#',c,'"/>');
        if (t==7) return string.concat('<g fill="#',c,'"><circle cx="',xs,'" cy="125" r="7"/><circle cx="',xs,'" cy="125" r="3" fill="#020308"/></g>');
        if (t==8) return string.concat('<path d="M',(x-7).toString(),' 131 L',xs,' 118 L',(x+7).toString(),' 131Z" fill="none" stroke="#',c,'" stroke-width="2"/>');
        if (left) return string.concat('<path d="M',(x-9).toString(),' 125 L',(x+7).toString(),' 120 L',(x+7).toString(),' 130Z" fill="#',c,'"/>');
        return string.concat('<path d="M',(x+9).toString(),' 125 L',(x-7).toString(),' 120 L',(x-7).toString(),' 130Z" fill="#',c,'"/>');
    }

    // -----------------------------------------------------------------------
    // Brow
    // -----------------------------------------------------------------------

    function brow(uint256 t, uint256 x, string memory c) external pure returns (string memory) {
        if (t==0) return "";
        string memory xm = (x-10).toString();
        string memory xp = (x+10).toString();
        if (t==1) return string.concat('<path d="M',xm,' 106 L',xp,' 104" stroke="#',c,'" stroke-width="2"/>');
        if (t==2) return string.concat('<path d="M',xm,' 108 L',xp,' 102" stroke="#',c,'" stroke-width="2"/>');
        if (t==3) return string.concat('<path d="M',xm,' 103 L',xp,' 108" stroke="#',c,'" stroke-width="2"/>');
        return string.concat('<path d="M',xm,' 106 Q',x.toString(),' 100 ',xp,' 106" stroke="#',c,'" stroke-width="2" fill="none"/>');
    }

    // -----------------------------------------------------------------------
    // Mouth
    // -----------------------------------------------------------------------

    function mouth(uint256 t, string memory cL, string memory cR) external pure returns (string memory) {
        if (t==0) return string.concat('<path d="M125 178 L150 180" stroke="#',cL,'" stroke-width="2" fill="none"/><path d="M150 180 L175 178" stroke="#',cR,'" stroke-width="2" fill="none"/>');
        if (t==1) return string.concat('<path d="M125 178 Q137 186 150 182" stroke="#',cL,'" stroke-width="2" fill="none"/><path d="M150 182 Q163 186 175 178" stroke="#',cR,'" stroke-width="2" fill="none"/>');
        if (t==2) return string.concat('<path d="M125 182 Q137 174 150 178" stroke="#',cL,'" stroke-width="2" fill="none"/><path d="M150 178 Q163 174 175 182" stroke="#',cR,'" stroke-width="2" fill="none"/>');
        if (t==3) return string.concat('<path d="M128 178 L140 182 L150 177" stroke="#',cL,'" stroke-width="2" fill="none"/><path d="M150 177 L160 182 L172 178" stroke="#',cR,'" stroke-width="2" fill="none"/>');
        return string.concat('<rect x="135" y="176" width="15" height="5" fill="#',cL,'" opacity=".8"/><rect x="150" y="176" width="15" height="5" fill="#',cR,'" opacity=".8"/>');
    }

    // -----------------------------------------------------------------------
    // Crown
    // -----------------------------------------------------------------------

    function crown(uint256 t, string memory cL, string memory cR, uint256 top) external pure returns (string memory) {
        if (t==0) return "";
        string memory o = top >= 55
            ? string.concat("translate(0,", (top-55).toString(), ")")
            : string.concat("translate(0,-", (55-top).toString(), ")");
        if (t==1) return string.concat('<g transform="',o,'"><path d="M118 70 L122 52 M135 62 L138 46 M150 60 L150 42 M165 62 L162 46 M182 70 L178 52" stroke="#',cL,'" stroke-width="2.5" filter="url(#g)"/></g>');
        if (t==2) return string.concat('<g transform="',o,'"><path d="M118 70 Q150 50 182 70" stroke="#',cR,'" stroke-width="2" fill="none" opacity=".7"/></g>');
        return string.concat('<g transform="',o,'"><path d="M122 66 L130 56 L138 66 L146 54 L150 64 L154 54 L162 66 L170 56 L178 66" stroke="#',cL,'" stroke-width="2" fill="none"/></g>');
    }

    // -----------------------------------------------------------------------
    // Backdrop
    // -----------------------------------------------------------------------

    function backdrop(uint256 t, string memory c) external pure returns (string memory) {
        if (t==0) return "";
        if (t==1) return '<rect width="300" height="300" fill="url(#bd)"/>';
        if (t==2) return string.concat('<rect x="120" y="0" width="60" height="300" fill="#',c,'" opacity=".05"/>');
        if (t==3) return string.concat('<g opacity=".22" fill="#',c,'"><circle cx="50" cy="44" r="1"/><circle cx="150" cy="70" r="1"/><circle cx="250" cy="50" r="1"/><circle cx="90" cy="150" r="1"/><circle cx="210" cy="170" r="1"/><circle cx="150" cy="240" r="1"/></g>');
        return string.concat('<rect x="0" y="0" width="300" height="150" fill="#',c,'" opacity=".03"/>');
    }

    // -----------------------------------------------------------------------
    // Undereye
    // -----------------------------------------------------------------------

    function undereye(uint256 t, string memory cL, string memory cR) external pure returns (string memory) {
        if (t==0) return "";
        if (t==1) return string.concat('<path d="M127 136 Q125 150 127 158" stroke="#',cL,'" stroke-width="1.5" fill="none" opacity=".7"/>');
        if (t==2) return string.concat('<path d="M121 140 L133 148 M167 148 L179 140" stroke="#',cL,'" stroke-width="1.5" opacity=".6"/>');
        return string.concat('<circle cx="127" cy="142" r="1.5" fill="#',cL,'"/><circle cx="173" cy="142" r="1.5" fill="#',cR,'"/>');
    }

    // -----------------------------------------------------------------------
    // Aura + Shatter
    // -----------------------------------------------------------------------

    function aura(string memory c) external pure returns (string memory) {
        return string.concat('<g filter="url(#g)" fill="none" opacity=".4"><circle cx="150" cy="140" r="108" stroke="#',c,'" stroke-width="1"/><circle cx="150" cy="140" r="98" stroke="#',c,'" stroke-width="1" opacity=".5"/></g>');
    }

    function shatter(string memory c) external pure returns (string memory) {
        return string.concat('<g stroke="#',c,'" stroke-width=".8" opacity=".45" fill="none"><path d="M150 140 L120 110 M150 140 L180 105 M150 140 L115 170 M150 140 L185 175 M150 140 L150 100"/></g>');
    }
}
