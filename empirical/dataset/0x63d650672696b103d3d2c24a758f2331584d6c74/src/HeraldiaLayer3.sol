// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

library HeraldiaLayer3 {

    struct L3State {
        uint16 G;
        uint16 L3A;
        uint16 L3B;
        uint16 cols;
        uint16 rows;
        uint16 splitCol;
        uint16 splitRow;
        uint16 rowSplit1;
        uint16 rowSplit2;
        uint8 fillAreaType;
        uint8 fillTypeA;
        uint8 fillTypeB;
        uint8 patternStyle;
    }

    struct RenderParams {
        uint16 L3A;
        uint16 L3B;
        uint8 fillAreaType;
        uint8 fillTypeA;
        uint8 fillTypeB;
        uint8 patternStyle;
        uint32 backfillRatioRand;
        uint32[] caseChoices;
        uint32[] shuffleRands;
        uint32[] neighborPickRands;
        uint32[] styleRands;
    }

    function renderPath(RenderParams calldata p) external pure returns (string memory) {
        L3State memory s;
        s.L3A = p.L3A;
        s.L3B = p.L3B;
        s.G = s.L3A < s.L3B ? s.L3A : s.L3B;
        s.cols = 960 / s.G;
        s.rows = 960 / s.G;
        s.splitCol = s.cols / 2;
        s.splitRow = s.rows / 2;
        s.rowSplit1 = s.rows / 3;
        s.rowSplit2 = (s.rows * 2) / 3;
        s.fillAreaType = p.fillAreaType;
        s.fillTypeA = p.fillTypeA;
        s.fillTypeB = p.fillTypeB;
        s.patternStyle = p.patternStyle;

        bytes memory out = new bytes(90000);
        uint256 ptr;
        assembly { ptr := add(out, 32) }

        bytes memory grid = new bytes(uint256(s.cols) * uint256(s.rows));

        uint256 maxCells = uint256(s.cols) * uint256(s.rows);
        bytes memory nullSquares = new bytes(maxCells * 2);
        uint16 nullCnt;
        uint16 caseIdx;
        uint16 styleIdx;

        unchecked {
            for (uint16 j = 0; j < s.rows; j++) {
                uint16 rowBase = j * s.cols;
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

                    if (!shouldProcess) {
                        if (areaType == 2) {
                            uint256 offset = uint256(nullCnt) * 2;
                            nullSquares[offset]     = bytes1(uint8(i));
                            nullSquares[offset + 1] = bytes1(uint8(j));
                            nullCnt++;
                        }
                        continue;
                    }

                    uint8 caseChoice = uint8(p.caseChoices[caseIdx] % 50) + 1;
                    caseIdx++;

                    grid[rowBase + i] = bytes1(caseChoice);

                    ptr = _renderCaseNoRng(
                        ptr,
                        caseChoice,
                        i * s.G,
                        j * s.G,
                        curG,
                        s.patternStyle,
                        p.styleRands[styleIdx]
                    );
                    styleIdx++;
                }
            }
        }

        if (nullCnt != 0) {
            ptr = _backfill(s, nullSquares, nullCnt, maxCells, styleIdx, p, ptr, grid);
        }

        uint256 used;
        assembly {
            used := sub(ptr, add(out, 32))
            mstore(out, used)
        }

        return string(out);
    }

    function _areaType(L3State memory s, uint16 i, uint16 j) private pure returns (uint8) {
        uint8 fa = s.fillAreaType;
        if (fa == 0) return s.fillTypeA;
        if (fa == 1) return i < s.splitCol ? s.fillTypeA : s.fillTypeB;
        if (fa == 2) return j < s.splitRow ? s.fillTypeA : s.fillTypeB;
        if (fa == 3) {
            bool mainDiag = (i < s.splitCol && j < s.splitRow) || (i >= s.splitCol && j >= s.splitRow);
            return mainDiag ? s.fillTypeA : s.fillTypeB;
        }

        uint8 colRegion = i < s.splitCol ? 0 : 1;
        uint8 rowRegion = j < s.rowSplit1 ? 0 : (j < s.rowSplit2 ? 1 : 2);
        return ((rowRegion + colRegion) & 1) == 0 ? s.fillTypeA : s.fillTypeB;
    }

    function _backfill(
        L3State memory s,
        bytes memory nullSquares,
        uint16 nullCnt,
        uint256 maxCells,
        uint16 styleIdx,
        RenderParams calldata p,
        uint256 ptr,
        bytes memory grid
    ) private pure returns (uint256) {

        bytes memory candidates = new bytes(maxCells * 2);
        uint16 candCnt;

        unchecked {
            for (uint16 n = 0; n < nullCnt; n++) {
                uint256 offset = uint256(n) * 2;
                uint8 i0 = uint8(nullSquares[offset]);
                uint8 j0 = uint8(nullSquares[offset + 1]);
                if (_areaType(s, i0, j0) == 2) {
                    uint256 cOffset = uint256(candCnt) * 2;
                    candidates[cOffset]     = bytes1(i0);
                    candidates[cOffset + 1] = bytes1(j0);
                    candCnt++;
                }
            }
        }

        if (candCnt == 0) return ptr;

        uint256 ratio = 200000000 + ((uint256(p.backfillRatioRand) * 50000000) >> 32);
        uint16 numToFill = uint16((uint256(candCnt) * ratio) / 1e9);
        if (numToFill == 0) numToFill = 1;
        if (numToFill > candCnt) numToFill = candCnt;

        uint16 currentIndex = candCnt;
        uint16 shuffleIdx;
        unchecked {
            while (currentIndex != 0) {
                uint16 randomIndex =
                    uint16((uint256(p.shuffleRands[shuffleIdx]) * uint256(currentIndex)) >> 32);
                shuffleIdx++;
                currentIndex--;

                uint256 aOff = uint256(currentIndex) * 2;
                uint256 bOff = uint256(randomIndex) * 2;

                bytes1 tmpI = candidates[aOff];
                bytes1 tmpJ = candidates[aOff + 1];
                candidates[aOff]     = candidates[bOff];
                candidates[aOff + 1] = candidates[bOff + 1];
                candidates[bOff]     = tmpI;
                candidates[bOff + 1] = tmpJ;
            }
        }

        uint16 localStyleIdx = styleIdx;

        unchecked {
            for (uint16 n = 0; n < numToFill; n++) {
                uint256 offset = uint256(n) * 2;
                uint8 i2 = uint8(candidates[offset]);
                uint8 j2 = uint8(candidates[offset + 1]);

                uint8 areaType3 = _areaType(s, i2, j2);
                uint16 drawG = areaType3 == 1 ? s.L3A : s.L3B;
                uint16 gridX = uint16(i2) * s.G;
                uint16 gridY = uint16(j2) * s.G;

                uint8 patternToUse = _neighborPickNoRng(s, i2, j2, grid, p.neighborPickRands[n]);

                if (patternToUse != 0) {
                    ptr = _renderCaseNoRng(
                        ptr,
                        patternToUse,
                        gridX,
                        gridY,
                        drawG,
                        s.patternStyle,
                        p.styleRands[localStyleIdx]
                    );
                    localStyleIdx++;
                    grid[uint16(j2) * s.cols + i2] = bytes1(patternToUse);
                }
            }
        }

        return ptr;
    }

    function _neighborPickNoRng(
        L3State memory s,
        uint8 i,
        uint8 j,
        bytes memory grid,
        uint32 rand
    ) private pure returns (uint8) {
        uint8[8] memory neighborPatterns;
        uint8 neighborCnt;

        unchecked {
            for (int8 dy = -1; dy <= 1; dy++) {
                for (int8 dx = -1; dx <= 1; dx++) {
                    if (dx == 0 && dy == 0) continue;

                    int16 ni = int16(uint16(i)) + dx;
                    int16 nj = int16(uint16(j)) + dy;

                    if (
                        ni >= 0 &&
                        ni < int16(uint16(s.cols)) &&
                        nj >= 0 &&
                        nj < int16(uint16(s.rows))
                    ) {
                        uint8 pat = uint8(grid[uint16(uint16(nj)) * s.cols + uint16(uint16(ni))]);
                        if (pat != 0) {
                            neighborPatterns[neighborCnt++] = pat;
                        }
                    }
                }
            }
        }

        if (neighborCnt == 0) return 1;
        return neighborPatterns[uint8((uint256(rand) * neighborCnt) >> 32)];
    }

    function _renderCaseNoRng(
        uint256 ptr,
        uint8 caseChoice,
        uint16 gridX,
        uint16 gridY,
        uint16 G,
        uint8 patternStyle,
        uint32 styleRand
    ) private pure returns (uint256) {
        uint8 rs = patternStyle;
        if (rs == 4) {
            rs = uint8(styleRand % 3) + 1;
        }

        uint16 size = G / 4;
        uint16 center = G / 2 - size / 2;
        (uint256 packed, uint8 pairs) = _patternPacked(caseChoice);

        unchecked {
            for (uint8 k = 0; k < pairs; k++) {
                uint8 xy = uint8(packed >> (k * 8));
                uint8 xm = xy >> 4;
                uint8 ym = xy & 0x0F;

                uint16 x = gridX + (xm == 9 ? center : uint16(xm) * size);
                uint16 y = gridY + (ym == 9 ? center : uint16(ym) * size);

                ptr = _renderPatternSquare(ptr, x, y, size, rs);
            }
        }

        return ptr;
    }

    function _renderPatternSquare(
        uint256 ptr,
        uint16 x,
        uint16 y,
        uint16 size,
        uint8 style
    ) private pure returns (uint256) {
        uint16 th = (size + 2) / 4;

        if (style == 1) {
            return _sq(ptr, x, y, size, size);
        }
        if (style == 2) {
            uint16 inner = size - th * 2;
            return _sq(ptr, x, y, inner, inner);
        }
        if (style == 3) {
            uint16 half = (size - th) / 2;
            ptr = _sq(ptr, x + half, y, th, size);
            return _sq(ptr, x, y + half, size, th);
        }
        return ptr;
    }

    function _sq(
        uint256 ptr,
        uint16 x,
        uint16 y,
        uint16 w,
        uint16 h
    ) private pure returns (uint256) {
        assembly {
            function wn(p, val) -> np {
                switch val
                case 0 {
                    mstore8(p, 48)
                    np := add(p, 1)
                }
                default {
                    switch lt(val, 10)
                    case 1 {
                        mstore8(p, add(48, val))
                        np := add(p, 1)
                    }
                    default {
                        switch lt(val, 100)
                        case 1 {
                            mstore8(p, add(48, div(val, 10)))
                            mstore8(add(p, 1), add(48, mod(val, 10)))
                            np := add(p, 2)
                        }
                        default {
                            switch lt(val, 1000)
                            case 1 {
                                mstore8(p, add(48, div(val, 100)))
                                let r := mod(val, 100)
                                mstore8(add(p, 1), add(48, div(r, 10)))
                                mstore8(add(p, 2), add(48, mod(r, 10)))
                                np := add(p, 3)
                            }
                            default {
                                mstore8(p, add(48, div(val, 1000)))
                                let r1 := mod(val, 1000)
                                mstore8(add(p, 1), add(48, div(r1, 100)))
                                let r2 := mod(r1, 100)
                                mstore8(add(p, 2), add(48, div(r2, 10)))
                                mstore8(add(p, 3), add(48, mod(r2, 10)))
                                np := add(p, 4)
                            }
                        }
                    }
                }
            }

            mstore8(ptr, 0x4D)
            ptr := add(ptr, 1)
            ptr := wn(ptr, and(x, 0xffff))
            mstore8(ptr, 0x20)
            ptr := add(ptr, 1)
            ptr := wn(ptr, and(y, 0xffff))
            mstore8(ptr, 0x68)
            ptr := add(ptr, 1)
            ptr := wn(ptr, and(w, 0xffff))
            mstore8(ptr, 0x76)
            ptr := add(ptr, 1)
            ptr := wn(ptr, and(h, 0xffff))
            mstore8(ptr, 0x68)
            mstore8(add(ptr, 1), 0x2D)
            ptr := add(ptr, 2)
            ptr := wn(ptr, and(w, 0xffff))
            mstore8(ptr, 0x7A)
            ptr := add(ptr, 1)
        }
        return ptr;
    }

    function _patternPacked(uint8 idx) private pure returns (uint256 packed, uint8 pairs) {
        if (idx == 1)  return (0x99, 1);
        if (idx == 2)  return (0x32023101, 4);
        if (idx == 3)  return (0x23132010, 4);
        if (idx == 4)  return (0x32021101, 4);
        if (idx == 5)  return (0x13212010, 4);
        if (idx == 6)  return (0x12023101, 4);
        if (idx == 7)  return (0x23132210, 4);
        if (idx == 8)  return (0x32023000, 4);
        if (idx == 9)  return (0x320221113000, 6);
        if (idx == 10) return (0x33133010, 4);
        if (idx == 11) return (0x331322213010, 6);
        if (idx == 12) return (0x33033000, 4);
        if (idx == 13) return (0x330321113000, 6);
        if (idx == 14) return (0x330322123000, 6);
        if (idx == 15) return (0x3303221221113000, 8);
        if (idx == 16) return (0x33221100, 4);
        if (idx == 17) return (0x03122130, 4);
        if (idx == 18) return (0x330322113000, 6);
        if (idx == 19) return (0x330312213000, 6);
        if (idx == 20) return (0x13023120, 4);
        if (idx == 21) return (0x23320110, 4);
        if (idx == 22) return (0x331302312000, 6);
        if (idx == 23) return (0x230332013010, 6);
        if (idx == 24) return (0x233212210110, 6);
        if (idx == 25) return (0x132202311120, 6);
        if (idx == 26) return (0x233222110110, 6);
        if (idx == 27) return (0x131202312120, 6);
        if (idx == 28) return (0x2303122101303010, 8);
        if (idx == 29) return (0x3313220231112000, 8);
        if (idx == 30) return (0x33223111302000, 7);
        if (idx == 31) return (0x33130322021100, 7);
        if (idx == 32) return (0x03122101301000, 7);
        if (idx == 33) return (0x33230332122130, 7);
        if (idx == 34) return (0x2332120231210110, 8);
        if (idx == 35) return (0x1332220231110120, 8);
        if (idx == 36) return (0x231322023111201036, 9);
        if (idx == 37) return (0x2313321221012010, 8);
        if (idx == 38) return (0x33032212213000, 7);
        if (idx == 39) return (0x33032221113000, 7);
        if (idx == 40) return (0x33031221113000, 7);
        if (idx == 41) return (0x33032212113000, 7);
        if (idx == 42) return (0x2303322211013010, 8);
        if (idx == 43) return (0x3313120231212000, 8);
        if (idx == 44) return (0x33320100, 4);
        if (idx == 45) return (0x03023130, 4);
        if (idx == 46) return (0x33231000, 4);
        if (idx == 47) return (0x13033020, 4);
        if (idx == 48) return (0x22122111, 4);
        if (idx == 49) return (0x3323322211011000, 8);
        if (idx == 50) return (0x1303120231213020, 8);
        return (0, 0);
    }
}