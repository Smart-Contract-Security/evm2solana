// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { HeraldiaTraits } from "./HeraldiaTraitsV2.sol";
import { HeraldiaLayer1 } from "./HeraldiaLayer1.sol";
import { HeraldiaLayer3 } from "./HeraldiaLayer3.sol";
import { HeraldiaEmblem } from "./HeraldiaEmblemV2.sol";
import { PRNGLib } from "./HeraldiaPRNG.sol";

interface IHeraldiaColorWrapper {
    function getColors(bytes32 dHash, bool isDarkTheme)
        external
        pure
        returns (string memory, string memory);
}

library HeraldiaPreviewV2 {
    using PRNGLib for PRNGLib.State;

    struct Layer3Rand {
        uint32 backfillRatioRand;
        uint32[] caseChoices;
        uint32[] shuffleRands;
        uint32[] neighborPickRands;
        uint32[] styleRands;
    }

    struct L3Init {
        uint16 L3A;
        uint16 L3B;
        uint16 G;
        uint16 cols;
        uint16 rows;
        uint8 fillAreaType;
        uint8 fillTypeA;
        uint8 fillTypeB;
    }

    function render(
        bytes32 sHash,
        bytes32 dHash,
        HeraldiaTraits.TokenTraits memory traits,
        address colorWrapper
    ) public pure returns (string memory svg, uint8 edgeTouchIndex) {
        string memory bgColor = traits.isDarkTheme ? "#ffffff" : "#000000";
        string memory emblemColor = traits.isDarkTheme ? "#000000" : "#ffffff";

        (string memory layer1Color, string memory layer3Color) =
            IHeraldiaColorWrapper(colorWrapper).getColors(dHash, traits.isDarkTheme);

        PRNGLib.State memory R = PRNGLib.init(dHash);

        uint32 l1vr = R.nextRange(5);
        uint32 l1cr = 0;
        if (l1vr + 1 == 2 || l1vr + 1 == 3) l1cr = R.nextRange(2);
        else if (l1vr + 1 == 4) l1cr = R.nextRange(4);
        else if (l1vr + 1 == 5) l1cr = R.nextRange(6);

        string memory layer1Path = HeraldiaLayer1.generatePath(
            l1vr,
            l1cr,
            R.nextRange(uint32(traits.bgTDivide - 1)) + 2,
            R.nextRange(2),
            uint8(traits.bgTSize),
            traits.bgTType
        );

        (L3Init memory s, Layer3Rand memory l3r) = _buildLayer3Data(R, traits.patternStyle, traits.emblemPSize);

        HeraldiaLayer3.RenderParams memory params = HeraldiaLayer3.RenderParams({
            L3A: s.L3A,
            L3B: s.L3B,
            fillAreaType: s.fillAreaType,
            fillTypeA: s.fillTypeA,
            fillTypeB: s.fillTypeB,
            patternStyle: traits.patternStyle,
            backfillRatioRand: l3r.backfillRatioRand,
            caseChoices: l3r.caseChoices,
            shuffleRands: l3r.shuffleRands,
            neighborPickRands: l3r.neighborPickRands,
            styleRands: l3r.styleRands
        });

        string memory layer3Path = HeraldiaLayer3.renderPath(params);

        string memory emblemPath;
        (emblemPath, edgeTouchIndex) = HeraldiaEmblem.generatePath(
            sHash,
            uint8(traits.emblemTSize),
            traits.emblemTMirror
        );

        svg = string(
            abi.encodePacked(
                '<svg xmlns="http://www.w3.org/2000/svg" width="960" height="960" viewBox="0 0 960 960" shape-rendering="crispEdges">',
                '<rect width="960" height="960" fill="', bgColor, '"/>',
                '<path fill="', layer1Color, '" d="', layer1Path, '"/>',
                '<path fill="', layer3Color, '" d="', layer3Path, '"/>',
                '<path fill="', emblemColor, '" d="', emblemPath, '"/>',
                '</svg>'
            )
        );
    }

    function _buildLayer3Data(
        PRNGLib.State memory R,
        uint8 patternStyle,
        uint8 emblemPSize
    ) private pure returns (L3Init memory s, Layer3Rand memory l3r) {
        uint32 l3aRand = R.nextRange(2);
        uint32 l3bRand = R.nextRange(2);
        uint32 fillAreaRand = R.nextRange(5);
        uint32 fillTypeRand = R.nextRange(2);

        uint8 divA = (l3aRand & 1) == 0 ? 10 : emblemPSize;
        uint8 divB = (l3bRand & 1) == 0 ? 10 : emblemPSize;

        s.L3A = 960 / uint16(divA);
        s.L3B = 960 / uint16(divB);
        s.G = s.L3A < s.L3B ? s.L3A : s.L3B;
        s.cols = 960 / s.G;
        s.rows = 960 / s.G;
        s.fillAreaType = uint8(fillAreaRand % 5);
        s.fillTypeA = uint8(fillTypeRand & 1) + 1;
        s.fillTypeB = s.fillTypeA == 1 ? 2 : 1;

        uint16 mainCount = _countMainProcessed(s);

        l3r.caseChoices = new uint32[](500);
        l3r.styleRands = new uint32[](500);

        unchecked {
            for (uint16 i = 0; i < mainCount; i++) {
                l3r.caseChoices[i] = R.nextRange(50);

                if (patternStyle == 4) {
                    l3r.styleRands[i] = R.nextRange(3);
                }
            }

            if (patternStyle == 4) {
                for (uint16 i = mainCount; i < mainCount + 100; i++) {
                    l3r.styleRands[i] = R.nextRange(3);
                }
            }
        }

        l3r.backfillRatioRand = R.next();
        l3r.shuffleRands = _buildArr500Raw(R);
        l3r.neighborPickRands = _buildArr500Raw(R);
    }

    function _countMainProcessed(L3Init memory s) private pure returns (uint16 cnt) {
        unchecked {
            for (uint16 j = 0; j < s.rows; j++) {
                for (uint16 i = 0; i < s.cols; i++) {
                    uint8 areaType = _areaType(s, i, j);
                    uint16 curG = areaType == 1 ? s.L3A : s.L3B;
                    uint16 factor = curG / s.G;

                    if (curG > s.G && (i % factor != 0 || j % factor != 0)) continue;

                    bool shouldProcess = areaType == 1;
                    if (areaType == 2) {
                        uint16 I = i / factor;
                        uint16 J = j / factor;
                        shouldProcess = (J & 1) == 0 && (I & 1) == 0;
                    }

                    if (shouldProcess) cnt++;
                }
            }
        }
    }

    function _areaType(L3Init memory s, uint16 i, uint16 j) private pure returns (uint8) {
        uint16 splitCol = s.cols / 2;
        uint16 splitRow = s.rows / 2;
        uint16 rowSplit1 = s.rows / 3;
        uint16 rowSplit2 = (s.rows * 2) / 3;

        uint8 fa = s.fillAreaType;
        if (fa == 0) return s.fillTypeA;
        if (fa == 1) return i < splitCol ? s.fillTypeA : s.fillTypeB;
        if (fa == 2) return j < splitRow ? s.fillTypeA : s.fillTypeB;
        if (fa == 3) {
            bool mainDiag = (i < splitCol && j < splitRow) || (i >= splitCol && j >= splitRow);
            return mainDiag ? s.fillTypeA : s.fillTypeB;
        }

        uint8 colRegion = i < splitCol ? 0 : 1;
        uint8 rowRegion = j < rowSplit1 ? 0 : (j < rowSplit2 ? 1 : 2);
        return ((rowRegion + colRegion) & 1) == 0 ? s.fillTypeA : s.fillTypeB;
    }

    function _buildArr500Raw(PRNGLib.State memory R) private pure returns (uint32[] memory arr) {
        arr = new uint32[](500);
        unchecked {
            for (uint256 i = 0; i < 500; i++) {
                arr[i] = R.next();
            }
        }
    }
}
