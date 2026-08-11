// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Base64} from "solady/src/utils/Base64.sol";
import {LibString} from "solady/src/utils/LibString.sol";
import {DaemonAnimationData} from "./DaemonAnimationData.sol";
import {DaemonArtData} from "./DaemonArtData.sol";
import {DaemonCorruption} from "./DaemonCorruption.sol";
import {DaemonTraitSet, DaemonTraits} from "./DaemonTraits.sol";
import {DaemonTypeFixedData} from "./DaemonTypeFixedData.sol";

struct DaemonRenderRequest {
    uint256 objectId;
    uint256 originSwapBlock;
    uint256 seed;
    uint256 traitWord;
    bytes32 corruptionState;
    bytes32 poolId;
    uint64 corruptionEpoch;
    uint8 tier;
    bool frozen;
}

contract DaemonRenderer {
    using LibString for uint256;

    uint8 private constant SIZE = 24;
    string private constant GLITCH_KEY_TIMES = "0;.2564;.2714;.2821;.2949;.3205;.6026;.6175;.6282;.6410;1";
    string private constant ANIM_DUR = "4.68s";
    uint8 private constant REGULAR_LASER_EYES_ID = 15;
    uint8 private constant RGBCMY_LASER_EYES_ID = 16;
    uint8 private constant FIXED_COLOR_3D_EYES_ID = 19;
    uint8 private constant ET_TYPE_ID = 8;
    uint8 private constant WHITE_AURA_PALETTE_ID = DaemonArtData.PALETTE_COUNT;
    uint8 private constant RGBCMY_PALETTE_ID = DaemonArtData.PALETTE_COUNT + 1;
    uint8 private constant BLACK_FACE_PALETTE_ID = DaemonArtData.PALETTE_COUNT + 2;

    constructor(string memory) {}

    function tokenURI(DaemonRenderRequest memory request) external pure returns (string memory) {
        bool animated = request.tier >= 10;
        string memory svg = animated ? renderAnimatedSvg(request) : renderSvg(request);
        string memory image = string.concat("data:image/svg+xml;base64,", Base64.encode(bytes(svg)));
        string memory objectId = request.objectId.toString();
        string memory json = string.concat(
            '{"name":"Test Token #',
            objectId,
            '","description":"On-chain generative art.",',
            '"image":"',
            image,
            '","attributes":',
            attributesJson(request),
            "}"
        );
        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    function renderSvg(DaemonRenderRequest memory request) public pure returns (string memory) {
        return _renderSvg(request, false);
    }

    function renderAnimatedSvg(DaemonRenderRequest memory request) public pure returns (string memory) {
        return _renderSvg(request, true);
    }

    function _renderSvg(DaemonRenderRequest memory request, bool animated) private pure returns (string memory) {
        DaemonTraitSet memory traits = DaemonTraits.unpack(request.traitWord);
        bool animatedTier10 = animated && request.tier >= 10;
        bool reflected = DaemonTraits.isReflected(request.traitWord);
        string memory svg = "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' shape-rendering='crispEdges'>";
        if (animatedTier10) svg = string.concat(svg, _invertFilterDef());
        if (reflected) svg = string.concat(svg, "<g transform='matrix(-1,0,0,1,24,0)'>");
        svg = string.concat(
            svg, animatedTier10 ? DaemonAnimationData.crtBackground(traits.background) : _background(traits.background)
        );

        uint24[24] memory typeRows = DaemonArtData.typeRows(traits.daemonType);
        bool cleanBody = request.tier >= 5;
        bool showAura = request.tier >= 10;
        bool invertedBody = DaemonTraits.hasInvertedBody(request.traitWord);
        bool fixedColorType = traits.daemonType == ET_TYPE_ID;
        bool renderInvertedBody = invertedBody && !fixedColorType;
        uint24[24] memory bodyRows = cleanBody
            ? typeRows
            : DaemonCorruption.mutate(
                typeRows,
                request.seed,
                request.objectId,
                request.corruptionState,
                request.corruptionEpoch,
                request.tier,
                traits.glitchType,
                false
            );
        string memory bodyColor = renderInvertedBody ? "#f0f0f0" : "#0f0f0f";
        bool mono = DaemonTraits.isMono(request.traitWord);
        bool rgbcmyAura = traits.shadowPalette == RGBCMY_PALETTE_ID;
        bool whiteAura = traits.shadowPalette == WHITE_AURA_PALETTE_ID;
        string memory auraColor = traits.shadowPalette == BLACK_FACE_PALETTE_ID
            ? "#000000"
            : whiteAura || rgbcmyAura ? "#ffffff" : DaemonArtData.paletteColor(traits.shadowPalette);

        string memory auraSvg = "";
        if (showAura) {
            auraSvg = rgbcmyAura ? _rowsToRGBCMYAuraSvg(typeRows, -1, 0) : _rowsToSvg(typeRows, auraColor, -1, 0);
            svg = string.concat(svg, auraSvg);
            if (animatedTier10) svg = string.concat(svg, _animatedGlitchLayer(auraSvg));
        }
        if (!fixedColorType && !cleanBody && traits.glitchType == 4) {
            svg = string.concat(svg, _staticPixels(request, bodyColor));
        }

        svg = string.concat(svg, fixedColorType ? _etFixedBodySvg() : _rowsToSvg(bodyRows, bodyColor, 0, 0));

        string memory accentSvg = _accentSvg(traits, request.traitWord, mono, renderInvertedBody);
        svg = string.concat(svg, animatedTier10 ? string.concat(accentSvg, _animatedGlitchLayer(accentSvg)) : accentSvg);

        return string.concat(svg, reflected ? "</g></svg>" : "</svg>");
    }

    function attributesJson(DaemonRenderRequest memory request) public pure returns (string memory) {
        DaemonTraitSet memory traits = DaemonTraits.unpack(request.traitWord);
        string memory attrs = string.concat(
            "[",
            _strAttr("Mutation State", request.frozen ? "Frozen" : "Live"),
            ",",
            _numAttr("Object ID", request.objectId),
            ",",
            _numAttr("Spawn Block", request.originSwapBlock),
            ",",
            _strAttr("Background", _backgroundHexPair(traits.background)),
            ",",
            _strAttr("Type", DaemonArtData.typeName(traits.daemonType)),
            ",",
            _strAttr(
                "Eyes",
                DaemonTraits.isMono(request.traitWord)
                    ? DaemonArtData.monoEyesName(traits.eyes % DaemonArtData.MONOEYES_COUNT)
                    : _eyesName(traits.eyes)
            )
        );
        if (DaemonTraits.hasMouth(request.traitWord)) {
            attrs = string.concat(attrs, ",", _strAttr("Mouth", DaemonArtData.mouthName(traits.mouth)));
        }
        if (!request.frozen || request.tier < 5) {
            attrs = string.concat(attrs, ",", _strAttr("Corruption", DaemonArtData.glitchTypeName(traits.glitchType)));
        } else if (request.tier >= 5) {
            attrs = string.concat(attrs, ",", _strAttr("Corruption", "Sanitized"));
        }
        attrs = string.concat(attrs, ",", _strAttr("Eye Color", _eyeColorName(traits.eyes, request.traitWord)));
        if (DaemonTraits.hasMouth(request.traitWord)) {
            attrs = string.concat(
                attrs, ",", _strAttr("Mouth Color", _mouthColorName(request.traitWord, traits.mouthPalette))
            );
        }
        if (DaemonTraits.hasInvertedBody(request.traitWord) && traits.daemonType != ET_TYPE_ID) {
            attrs = string.concat(attrs, ",", _strAttr("Body Color", "F0F0F0"));
        }
        if (DaemonTraits.isReflected(request.traitWord)) {
            attrs = string.concat(attrs, ",", _strAttr("Effect", "Reflected"));
        }
        if (request.tier >= 10) {
            attrs = string.concat(
                attrs,
                ",",
                _strAttr("Aura", "On"),
                ",",
                _strAttr("Aura Color", _facePaletteName(traits.shadowPalette)),
                ",",
                _boolAttr("animation", true)
            );
        }
        if (DaemonTraits.hasAccessory(request.traitWord)) {
            attrs = string.concat(attrs, ",", _strAttr("Signal", DaemonArtData.accessoryName(traits.accessory)));
        }
        attrs = string.concat(
            attrs,
            ",",
            _strAttr("Upgrade Tier", _tierName(request.tier)),
            ",",
            _numAttr("Redeemable Tokens", 1),
            ",",
            _numAttr("Tokens Burned For Upgrade", _burnedForTier(request.tier)),
            "]"
        );
        return attrs;
    }

    function _background(uint8 id) private pure returns (string memory svg) {
        (string memory evenRow, string memory oddRow) = DaemonArtData.backgroundColors(id);
        for (uint8 y = 0; y < SIZE; ++y) {
            svg = string.concat(
                svg,
                "<rect x='0' y='",
                uint256(y).toString(),
                "' width='24' height='1' fill='",
                y % 2 == 0 ? evenRow : oddRow,
                "'/>"
            );
        }
    }

    function _backgroundHexPair(uint8 id) private pure returns (string memory) {
        if (id == 0) return "0F0F0F,000000";
        if (id == 1) return "2C2C2C,292929";
        if (id == 2) return "4E4E4E,525252";
        if (id == 3) return "D3D3D3,D6D6D6";
        revert("BAD_BG_ID");
    }

    function _rowsToSvg(uint24[24] memory rows, string memory color, int8 dx, int8 dy)
        private
        pure
        returns (string memory svg)
    {
        for (uint8 y = 0; y < SIZE; ++y) {
            uint24 row = rows[y];
            for (uint8 x = 0; x < SIZE; ++x) {
                if ((row & (uint24(1) << x)) == 0) continue;
                int16 px = int16(uint16(x)) + dx;
                int16 py = int16(uint16(y)) + dy;
                if (px < 0 || py < 0 || px >= int16(uint16(SIZE)) || py >= int16(uint16(SIZE))) continue;
                svg = string.concat(
                    svg,
                    "<rect x='",
                    uint256(uint16(px)).toString(),
                    "' y='",
                    uint256(uint16(py)).toString(),
                    "' width='1' height='1' fill='",
                    color,
                    "'/>"
                );
            }
        }
    }

    function _etFixedBodySvg() private pure returns (string memory svg) {
        for (uint8 color = 0; color < 3; ++color) {
            svg = string.concat(
                svg, _rowsToSvg(DaemonTypeFixedData.etRows(color), DaemonTypeFixedData.etColor(color), 0, 0)
            );
        }
    }

    function _rowsToRGBCMYAuraSvg(uint24[24] memory rows, int8 dx, int8 dy) private pure returns (string memory svg) {
        for (uint8 y = 0; y < SIZE; ++y) {
            uint24 row = rows[y];
            for (uint8 x = 0; x < SIZE; ++x) {
                if ((row & (uint24(1) << x)) == 0) continue;
                int16 px = int16(uint16(x)) + dx;
                int16 py = int16(uint16(y)) + dy;
                if (px < 0 || py < 0 || px >= int16(uint16(SIZE)) || py >= int16(uint16(SIZE))) continue;
                svg = string.concat(
                    svg,
                    "<rect x='",
                    uint256(uint16(px)).toString(),
                    "' y='",
                    uint256(uint16(py)).toString(),
                    "' width='1' height='1' fill='",
                    _rgbcmyAuraColor(y),
                    "'/>"
                );
            }
        }
    }

    function _accessoryRowsToSvg(uint8 accessory, bool mono, string memory auraColor)
        private
        pure
        returns (string memory)
    {
        uint24[24] memory rows = DaemonArtData.accessoryRows(accessory);
        if (mono) return _rowsToSvg(rows, "#ffffff", 0, 0);
        return _rowsToSvg(rows, auraColor, 0, 0);
    }

    function _accentSvg(DaemonTraitSet memory traits, uint256 traitWord, bool mono, bool invertedBody)
        private
        pure
        returns (string memory svg)
    {
        if (DaemonTraits.hasAccessory(traitWord)) {
            svg =
                _appendAccessorySvg("", traits.accessory, mono, _signalColor(traits.shadowPalette, traits.facePalette));
        }
        svg = string.concat(svg, _eyesToSvg(traits.eyes, traits.facePalette, mono, invertedBody));
        if (DaemonTraits.hasMouth(traitWord)) {
            svg = string.concat(svg, _mouthToSvg(traits.mouth, traits.mouthPalette, mono, invertedBody));
        }
    }

    function _appendAccessorySvg(string memory svg, uint8 accessory, bool mono, string memory paintColor)
        private
        pure
        returns (string memory)
    {
        if (DaemonArtData.accessoryUsesFixedColors(accessory)) {
            for (uint8 color = 0; color < DaemonArtData.accessoryFixedColorCount(accessory); ++color) {
                svg = string.concat(
                    svg,
                    _rowsToSvg(
                        DaemonArtData.accessoryFixedColorRows(accessory, color),
                        DaemonArtData.accessoryFixedColor(accessory, color),
                        0,
                        0
                    )
                );
            }
            return svg;
        }
        return string.concat(svg, _accessoryRowsToSvg(accessory, mono, paintColor));
    }

    function _eyesToSvg(uint8 eyesId, uint8 paletteId, bool mono, bool invertedBody)
        private
        pure
        returns (string memory svg)
    {
        if (mono) {
            uint8 id = eyesId % DaemonArtData.MONOEYES_COUNT;
            for (uint8 tone = 0; tone < DaemonArtData.MONO_FACE_TONE_COUNT; ++tone) {
                if (invertedBody && paletteId == RGBCMY_PALETTE_ID) {
                    svg =
                        string.concat(svg, _faceRowsToRGBCMYSvg(DaemonArtData.monoEyesToneRows(id, tone), tone, false));
                    continue;
                }
                string memory color =
                    invertedBody ? _faceToneColor(paletteId, tone) : DaemonArtData.monoFaceToneColor(tone);
                svg = string.concat(svg, _faceRowsToSvg(DaemonArtData.monoEyesToneRows(id, tone), color));
            }
            return svg;
        }

        uint8 fixedColorCount = DaemonArtData.eyesFixedColorCount(eyesId);
        if (fixedColorCount != 0) {
            for (uint8 color = 0; color < fixedColorCount; ++color) {
                svg = string.concat(
                    svg,
                    _faceRowsToSvg(
                        DaemonArtData.eyesFixedColorRows(eyesId, color), DaemonArtData.eyesFixedColor(eyesId, color)
                    )
                );
            }
            return svg;
        }

        if (paletteId == RGBCMY_PALETTE_ID) {
            bool verticalRGBCMY = eyesId == REGULAR_LASER_EYES_ID;
            for (uint8 tone = 0; tone < DaemonArtData.FACE_TONE_COUNT; ++tone) {
                svg = string.concat(
                    svg, _faceRowsToRGBCMYSvg(DaemonArtData.eyesToneRows(eyesId, tone), tone, verticalRGBCMY)
                );
            }
            return _appendFixedWhiteEye(svg, eyesId);
        }

        for (uint8 tone = 0; tone < DaemonArtData.FACE_TONE_COUNT; ++tone) {
            svg = string.concat(
                svg, _faceRowsToSvg(DaemonArtData.eyesToneRows(eyesId, tone), _faceToneColor(paletteId, tone))
            );
        }
        return _appendFixedWhiteEye(svg, eyesId);
    }

    function _mouthToSvg(uint8 mouthId, uint8 paletteId, bool mono, bool invertedBody)
        private
        pure
        returns (string memory svg)
    {
        if (mono) {
            if (!invertedBody) {
                svg = _faceRowsToSvg(DaemonArtData.mouthRows(mouthId), "#ffffff");
                return svg;
            }

            if (paletteId == RGBCMY_PALETTE_ID) {
                for (uint8 tone = 0; tone < DaemonArtData.FACE_TONE_COUNT; ++tone) {
                    svg = string.concat(
                        svg, _faceRowsToRGBCMYSvg(DaemonArtData.mouthToneRows(mouthId, tone), tone, false)
                    );
                }
                return svg;
            }

            for (uint8 tone = 0; tone < DaemonArtData.FACE_TONE_COUNT; ++tone) {
                svg = string.concat(
                    svg, _faceRowsToSvg(DaemonArtData.mouthToneRows(mouthId, tone), _faceToneColor(paletteId, tone))
                );
            }
            return svg;
        }

        if (paletteId == RGBCMY_PALETTE_ID) {
            for (uint8 tone = 0; tone < DaemonArtData.FACE_TONE_COUNT; ++tone) {
                svg = string.concat(svg, _faceRowsToRGBCMYSvg(DaemonArtData.mouthToneRows(mouthId, tone), tone, false));
            }
            return svg;
        }

        for (uint8 tone = 0; tone < DaemonArtData.FACE_TONE_COUNT; ++tone) {
            svg = string.concat(
                svg, _faceRowsToSvg(DaemonArtData.mouthToneRows(mouthId, tone), _faceToneColor(paletteId, tone))
            );
        }
    }

    function _faceRowsToSvg(uint24[24] memory rows, string memory color) private pure returns (string memory) {
        return _rowsToSvg(rows, color, 0, 0);
    }

    function _appendFixedWhiteEye(string memory svg, uint8 eyesId) private pure returns (string memory) {
        if (!DaemonArtData.eyesHasFixedWhite(eyesId)) return svg;
        return string.concat(svg, _faceRowsToSvg(DaemonArtData.eyesFixedWhiteRows(eyesId), "#ffffff"));
    }

    function _faceRowsToRGBCMYSvg(uint24[24] memory rows, uint8 tone, bool vertical)
        private
        pure
        returns (string memory)
    {
        return _rowsToRGBCMYFaceSvg(rows, tone, 0, 0, vertical);
    }

    function _rowsToRGBCMYFaceSvg(uint24[24] memory rows, uint8 tone, int8 dx, int8 dy, bool vertical)
        private
        pure
        returns (string memory svg)
    {
        for (uint8 y = 0; y < SIZE; ++y) {
            uint24 row = rows[y];
            for (uint8 x = 0; x < SIZE; ++x) {
                if ((row & (uint24(1) << x)) == 0) continue;
                int16 px = int16(uint16(x)) + dx;
                int16 py = int16(uint16(y)) + dy;
                if (px < 0 || py < 0 || px >= int16(uint16(SIZE)) || py >= int16(uint16(SIZE))) continue;
                svg = string.concat(
                    svg,
                    "<rect x='",
                    uint256(uint16(px)).toString(),
                    "' y='",
                    uint256(uint16(py)).toString(),
                    "' width='1' height='1' fill='",
                    _rgbcmyFaceToneColor(vertical ? y : x, tone),
                    "'/>"
                );
            }
        }
    }

    function _eyesName(uint8 eyesId) private pure returns (string memory) {
        if (eyesId == RGBCMY_LASER_EYES_ID) return "laser";
        return DaemonArtData.eyesName(eyesId);
    }

    function _eyeColorName(uint8 eyesId, uint256 traitWord) private pure returns (string memory) {
        if (!DaemonTraits.isMono(traitWord) && eyesId == RGBCMY_LASER_EYES_ID) return "RGBCMY";
        if (!DaemonTraits.isMono(traitWord) && eyesId == FIXED_COLOR_3D_EYES_ID) return "Original";
        if (DaemonTraits.isMono(traitWord) && !DaemonTraits.hasInvertedBody(traitWord)) return "Grayscale";
        DaemonTraitSet memory traits = DaemonTraits.unpack(traitWord);
        return _facePaletteName(traits.facePalette);
    }

    function _mouthColorName(uint256 traitWord, uint8 paletteId) private pure returns (string memory) {
        if (DaemonTraits.isMono(traitWord) && !DaemonTraits.hasInvertedBody(traitWord)) return "FFFFFF";
        return _facePaletteName(paletteId);
    }

    function _facePaletteName(uint8 paletteId) private pure returns (string memory) {
        if (paletteId == WHITE_AURA_PALETTE_ID) return "FFFFFF";
        if (paletteId == RGBCMY_PALETTE_ID) return "RGBCMY";
        if (paletteId == BLACK_FACE_PALETTE_ID) return "000000";
        return _paletteHex(paletteId);
    }

    function _paletteHex(uint8 paletteId) private pure returns (string memory) {
        if (paletteId == 0) return "FF0000";
        if (paletteId == 1) return "00FF00";
        if (paletteId == 2) return "0000FF";
        if (paletteId == 3) return "00FFFF";
        if (paletteId == 4) return "FF00FF";
        if (paletteId == 5) return "FFFF00";
        revert("BAD_NAME_ID");
    }

    function _faceToneColor(uint8 paletteId, uint8 tone) private pure returns (string memory) {
        if (paletteId == BLACK_FACE_PALETTE_ID) return "#000000";
        return DaemonArtData.paletteToneColor(paletteId, tone);
    }

    function _signalColor(uint8 auraPaletteId, uint8 facePaletteId) private pure returns (string memory) {
        if (auraPaletteId == RGBCMY_PALETTE_ID) return "#ffffff";
        uint8 signalPalette = uint8(facePaletteId % DaemonArtData.PALETTE_COUNT);
        return DaemonArtData.paletteColor(signalPalette);
    }

    function _invertFilterDef() private pure returns (string memory) {
        return "<defs><filter id='i' color-interpolation-filters='sRGB'><feColorMatrix type='matrix' values='-1 0 0 0 1 0 -1 0 0 1 0 0 -1 0 1 0 0 0 1 0'/></filter></defs>";
    }

    function _animatedGlitchLayer(string memory glitchSvg) private pure returns (string memory) {
        return string.concat(_glitchGhost(glitchSvg, "1 -1;-1 0;2 0"), _glitchGhost(glitchSvg, "-1 1;2 0;-1 0"));
    }

    function _glitchGhost(string memory glitchSvg, string memory burstTransforms) private pure returns (string memory) {
        return string.concat(
            "<g filter='url(#i)' opacity='0'><animate attributeName='opacity' calcMode='discrete' values='0;1;1;1;0;0;1;1;1;0;0' keyTimes='",
            GLITCH_KEY_TIMES,
            "' dur='",
            ANIM_DUR,
            "' repeatCount='indefinite'/><animateTransform attributeName='transform' type='translate' calcMode='discrete' values='0 0;",
            burstTransforms,
            ";0 0;0 0;",
            burstTransforms,
            ";0 0;0 0' keyTimes='",
            GLITCH_KEY_TIMES,
            "' dur='",
            ANIM_DUR,
            "' repeatCount='indefinite'/>",
            glitchSvg,
            "</g>"
        );
    }

    function _staticPixels(DaemonRenderRequest memory request, string memory color)
        private
        pure
        returns (string memory svg)
    {
        bytes32 entropy = keccak256(
            abi.encodePacked("TEST_STATIC_V3", request.seed, request.corruptionState, request.corruptionEpoch)
        );
        for (uint8 i = 0; i < 8; ++i) {
            uint8 x = uint8(uint256(entropy >> (i * 16))) % SIZE;
            uint8 y = uint8(uint256(entropy >> (i * 16 + 8))) % SIZE;
            svg = string.concat(
                svg,
                "<rect x='",
                uint256(x).toString(),
                "' y='",
                uint256(y).toString(),
                "' width='1' height='1' fill='",
                color,
                "'/>"
            );
        }
    }

    function _tierName(uint8 tier) private pure returns (string memory) {
        if (tier >= 10) return "10x";
        if (tier >= 5) return "5x";
        return "1x";
    }

    function _burnedForTier(uint8 tier) private pure returns (uint256) {
        if (tier >= 10) return 9;
        if (tier >= 5) return 4;
        return 0;
    }

    function _rgbcmyFaceToneColor(uint8 x, uint8 tone) private pure returns (string memory) {
        return DaemonArtData.paletteToneColor(uint8(x % DaemonArtData.PALETTE_COUNT), tone);
    }

    function _rgbcmyAuraColor(uint8 y) private pure returns (string memory) {
        return DaemonArtData.paletteColor(uint8((y / 2) % DaemonArtData.PALETTE_COUNT));
    }

    function _numAttr(string memory traitType, uint256 value) private pure returns (string memory) {
        return string.concat('{"display_type":"number","trait_type":"', traitType, '","value":', value.toString(), "}");
    }

    function _strAttr(string memory traitType, string memory value) private pure returns (string memory) {
        return string.concat('{"trait_type":"', traitType, '","value":"', value, '"}');
    }

    function _boolAttr(string memory traitType, bool value) private pure returns (string memory) {
        return string.concat('{"trait_type":"', traitType, '","value":', value ? "true" : "false", "}");
    }
}
