// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Base64} from "./src/utils/Base64.sol";
import {LibString} from "./src/utils/LibString.sol";
import {MirrorRendererParts} from "./MirrorRendererParts.sol";

/// @notice On-chain generative renderer for `mirror`.
/// @dev Heavy SVG primitives live in MirrorRendererParts (separate deploy).
///      RenderCtx struct keeps _svg stack depth below 16.
contract MirrorRenderer {
    using LibString for uint256;

    MirrorRendererParts public immutable parts;

    uint8 internal constant OWNER    = 0;
    uint8 internal constant STRANGER = 1;
    uint8 internal constant FORMER   = 2;

    constructor(address parts_) {
        parts = MirrorRendererParts(parts_);
    }

    // -----------------------------------------------------------------------
    // Traits
    // -----------------------------------------------------------------------

    struct Traits {
        uint256 shape; uint256 seam;  uint256 eyeL; uint256 eyeR;
        uint256 mouth; uint256 brow;  uint256 palL; uint256 palR;
        uint256 crown; uint256 mark;  uint256 bd;   uint256 ue;
        bool aura; bool shatter; bool pure_;
    }

    function _traits(uint256 id) internal view returns (Traits memory t) {
        uint256 s = uint256(keccak256(abi.encodePacked("mirror-split-v3", id)));
        t.shape   = parts.weighted(s, 0,  hex"14120c100a080f06");
        t.seam    = parts.weighted(s, 5,  hex"16140c12060a05");
        t.eyeL    = parts.weighted(s, 10, hex"14100e0a0508060407");
        t.eyeR    = parts.weighted(s, 16, hex"14100e0a0508060407");
        t.mouth   = parts.weighted(s, 22, hex"19160f0a08");
        t.brow    = parts.weighted(s, 26, hex"1e12100e0c");
        t.palL    = parts.weighted(s, 30, hex"0a0a0a0a0a0a0a0a0a0a0a0a0a0a");
        t.palR    = parts.weighted(s, 36, hex"0a0a0a0a0a0a0a0a0a0a0a0a0a0a");
        t.crown   = parts.weighted(s, 42, hex"460c0a08");
        t.aura    = parts.weighted(s, 46, hex"061313131312") == 0;
        t.mark    = parts.weighted(s, 50, hex"080a0e0e0e0e0e0e");
        t.bd      = parts.weighted(s, 54, hex"370e0c0a09");
        t.ue      = parts.weighted(s, 58, hex"460c0a08");
        t.shatter = parts.weighted(s, 62, hex"04101010101010") == 0;
        t.pure_   = (t.palL == t.palR);
    }

    // -----------------------------------------------------------------------
    // Render context — keeps _svg stack flat
    // -----------------------------------------------------------------------

    struct RenderCtx {
        string accL;
        string accR;
        string liteL;
        string liteR;
        string path;
        uint256 rx;
        uint256 ry;
        uint256 top;
    }

    function _buildCtx(Traits memory t, uint8 rel) internal view returns (RenderCtx memory c) {
        (c.accL, c.liteL) = parts.pal(t.palL);
        (c.accR, c.liteR) = parts.pal(t.palR);

        if (rel == STRANGER) {
            c.accL  = "3f3f46"; c.accR  = "3f3f46";
            c.liteL = "52525b"; c.liteR = "52525b";
        } else if (rel == FORMER) {
            c.accL  = "f87171"; c.accR  = "f87171";
            c.liteL = "7f1d1d"; c.liteR = "7f1d1d";
        }

        (c.path, c.rx, c.ry, c.top) = parts.face(t.shape);
    }

    // -----------------------------------------------------------------------
    // SVG entry points
    // -----------------------------------------------------------------------

    function svgFor(uint256 id, uint8 relation) public view returns (string memory) {
        return _svg(id, relation);
    }

    function svg(uint256 id) public view returns (string memory) {
        return _svg(id, OWNER);
    }

    function _svg(uint256 id, uint8 rel) internal view returns (string memory) {
        Traits memory t = _traits(id);
        RenderCtx memory c = _buildCtx(t, rel);

        // build in two halves to stay under stack depth
        string memory top = string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 300 300">',
            _defs(t, c.liteR),
            '<rect width="300" height="300" fill="url(#bg)"/>',
            rel == OWNER ? parts.backdrop(t.bd, c.liteR) : "",
            '<rect width="300" height="300" fill="url(#sl)"/>',
            (rel == OWNER && t.aura) ? parts.aura(c.liteR) : ""
        );
        string memory bot = string.concat(
            _faceFill(c.path, c.rx, c.ry),
            _outline(c.path, c.accL, c.accR, rel),
            _features(t, c, rel),
            _label(id, t, c.accL, rel),
            "</svg>"
        );
        return string.concat(top, bot);
    }

    // -----------------------------------------------------------------------
    // Defs
    // -----------------------------------------------------------------------

    function _defs(Traits memory t, string memory liteR) internal pure returns (string memory) {
        string memory bd = t.bd == 1
            ? string.concat(
                '<radialGradient id="bd" cx="50%" cy="35%" r="60%">',
                '<stop offset="0%" stop-color="#', liteR, '" stop-opacity=".12"/>',
                '<stop offset="100%" stop-color="#', liteR, '" stop-opacity="0"/></radialGradient>'
              )
            : "";
        string memory fixed_ = string.concat(
            '<defs>',
            '<filter id="g"><feGaussianBlur stdDeviation="2.5" result="x"/>',
            '<feMerge><feMergeNode in="x"/><feMergeNode in="SourceGraphic"/></feMerge></filter>',
            '<radialGradient id="bg" cx="50%" cy="40%" r="78%">',
            '<stop offset="0%" stop-color="#0e1420"/>',
            '<stop offset="60%" stop-color="#070a12"/>',
            '<stop offset="100%" stop-color="#020308"/></radialGradient>',
            '<pattern id="sl" width="8" height="8" patternUnits="userSpaceOnUse">',
            '<path d="M0 0H8" stroke="#fff" stroke-opacity=".035"/></pattern>'
        );
        return string.concat(fixed_, bd, '</defs>');
    }

    // -----------------------------------------------------------------------
    // Face geometry
    // -----------------------------------------------------------------------

    function _faceFill(string memory path, uint256 rx, uint256 ry) internal pure returns (string memory) {
        if (rx != 0) {
            return string.concat(
                '<ellipse cx="150" cy="140" rx="', rx.toString(),
                '" ry="', ry.toString(), '" fill="#0a0f18"/>'
            );
        }
        return string.concat(
            '<path d="', path, ' L150 224 Z" fill="#0a0f18"/>',
            '<g transform="translate(300,0) scale(-1,1)">',
            '<path d="', path, ' L150 224 Z" fill="#0a0f18"/></g>'
        );
    }

    function _outline(string memory path, string memory accL, string memory accR, uint8 rel) internal pure returns (string memory) {
        string memory dash = rel == STRANGER ? ' stroke-dasharray="5 6"' : "";
        return string.concat(
            '<g filter="url(#g)">',
            '<path d="', path, '" fill="none" stroke="#', accL, '" stroke-width="2"', dash, '/>',
            '<g transform="translate(300,0) scale(-1,1)">',
            '<path d="', path, '" fill="none" stroke="#', accR, '" stroke-width="2"', dash, '/></g></g>'
        );
    }

    // -----------------------------------------------------------------------
    // Features
    // -----------------------------------------------------------------------

    function _features(Traits memory t, RenderCtx memory c, uint8 rel) internal view returns (string memory) {
        if (rel == STRANGER) {
            return
                '<rect x="119" y="118" width="18" height="14" fill="#27272a"/>'
                '<rect x="163" y="118" width="18" height="14" fill="#27272a"/>'
                '<rect x="130" y="174" width="40" height="8" fill="#27272a"/>';
        }
        return string.concat(_featuresA(t, c, rel), _featuresB(t, c, rel));
    }

    /// @dev Upper half: shatter, crown, brows, eyes
    function _featuresA(Traits memory t, RenderCtx memory c, uint8 rel) internal view returns (string memory) {
        return string.concat(
            (rel == OWNER && t.shatter) ? parts.shatter(c.liteL) : "",
            parts.crown(t.crown, c.accL, c.accR, c.top),
            parts.brow(t.brow, 127, c.accL),
            parts.brow(t.brow, 173, c.accR),
            parts.eye(t.eyeL, 127, c.accL, true),
            parts.eye(t.eyeR, 173, c.accR, false)
        );
    }

    /// @dev Lower half: undereye, mouth, seam, mark, crack
    function _featuresB(Traits memory t, RenderCtx memory c, uint8 rel) internal view returns (string memory) {
        string memory mark = t.mark == 0
            ? string.concat('<circle cx="150" cy="92" r="4" fill="#', c.liteR, '"/>')
            : (t.mark == 1
                ? string.concat('<path d="M146 150 L150 158 L154 150" stroke="#', c.liteL, '" stroke-width="1.5" fill="none"/>')
                : "");
        string memory crack = rel == FORMER
            ? '<path d="M150 70 L138 120 L156 165 L142 215" stroke="#dc2626" stroke-width="1.5" fill="none" opacity=".8"/>'
              '<path d="M127 132 Q125 160 129 185" stroke="#dc2626" stroke-width="2" fill="none" opacity=".7"/>'
            : "";
        return string.concat(
            parts.undereye(t.ue, c.liteL, c.liteR),
            parts.mouth(t.mouth, c.liteL, c.liteR),
            parts.seam(t.seam, c.liteL),
            mark,
            crack
        );
    }

    // -----------------------------------------------------------------------
    // Label
    // -----------------------------------------------------------------------

    function _label(uint256 id, Traits memory t, string memory accL, uint8 rel) internal pure returns (string memory) {
        if (rel == STRANGER) {
            return
                '<text x="150" y="262" font-family="ui-monospace,monospace" font-size="12" fill="#a1a1aa" text-anchor="middle" letter-spacing="2">unknown wallet</text>'
                '<text x="150" y="282" font-family="ui-monospace,monospace" font-size="10" fill="#a1a1aa" text-anchor="middle" opacity=".75">"WHO ARE YOU?"</text>';
        }
        if (rel == FORMER) {
            return
                '<text x="150" y="262" font-family="ui-monospace,monospace" font-size="12" fill="#f87171" text-anchor="middle" letter-spacing="2">former holder</text>'
                '<text x="150" y="282" font-family="ui-monospace,monospace" font-size="10" fill="#f87171" text-anchor="middle" opacity=".75">"YOU LET ME GO"</text>';
        }
        string memory badges;
        if (t.pure_)   badges = " PURE";
        if (t.aura)    badges = string.concat(badges, " AURA");
        if (t.shatter) badges = string.concat(badges, " SHATTERED");
        return string.concat(
            '<text x="150" y="288" font-family="ui-monospace,monospace" font-size="8.5" fill="#', accL,
            '" text-anchor="middle" letter-spacing="1.5">mirror #', id.toString(), badges, "</text>"
        );
    }

    // -----------------------------------------------------------------------
    // tokenURI
    // -----------------------------------------------------------------------

    function tokenURI(uint256 id, uint8 relation) external view returns (string memory) {
        string memory image = Base64.encode(bytes(svgFor(id, relation)));
        Traits memory t = _traits(id);
        string memory json = string.concat(
            '{"name":"mirror #', id.toString(),
            '","description":"Two faces, one token. It looks different to its owner, a stranger, and those who let it go. On-chain.",',
            '"image":"data:image/svg+xml;base64,', image,
            '","attributes":[', _attributes(t), "]}"
        );
        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    function _attributes(Traits memory t) internal pure returns (string memory) {
        string memory a = string.concat(
            '{"trait_type":"Face","value":', t.shape.toString(),
            '},{"trait_type":"Seam","value":', t.seam.toString(),
            '},{"trait_type":"EyeL","value":', t.eyeL.toString(),
            '},{"trait_type":"EyeR","value":', t.eyeR.toString()
        );
        string memory b = string.concat(
            '},{"trait_type":"Crown","value":', t.crown.toString(),
            '},{"trait_type":"Aura","value":"', t.aura ? "Yes" : "No",
            '"},{"trait_type":"Shatter","value":"', t.shatter ? "Yes" : "No",
            '"},{"trait_type":"Pure","value":"', t.pure_ ? "Yes" : "No", '"}'
        );
        return string.concat(a, b);
    }
}
