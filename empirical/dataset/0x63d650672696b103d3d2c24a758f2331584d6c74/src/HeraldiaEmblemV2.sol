// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import "./HeraldiaPRNG.sol";

library HeraldiaEmblem {
    using PRNGLib for PRNGLib.State;

    function generatePath(
        bytes32 sHash,
        uint8 emblemTSize,
        uint8 mirrorStyle
    ) internal pure returns (string memory, uint8) {
        PRNGLib.State memory R = PRNGLib.init(sHash);
        uint16 gridSize = 960 / uint16(emblemTSize);
        uint8 gridCount = uint8(960 / gridSize);
        uint8 xMin = 0;
        uint8 xMax = uint8(480 / gridSize - 1);
        uint8 maxStep = (emblemTSize / 10) * 6;
        if (maxStep > 30) maxStep = 30;
        uint8 minSeg = emblemTSize;

        uint256[120] memory grid;

        if (mirrorStyle == 0) {
            uint8 yMax = uint8(480 / gridSize - 1);
            _calcPath(R, grid, xMin, xMax, 0, yMax, maxStep, minSeg);
            _mirY(grid, xMin, xMax, 0, yMax);
            _mirX(grid, xMin, xMax, gridCount);

        } else if (mirrorStyle == 1) {
            uint8 yMax = uint8(960 / gridSize - 1);
            _calcPath(R, grid, xMin, xMax, 0, yMax, maxStep, minSeg);
            _mirX(grid, xMin, xMax, gridCount);

        } else {
            uint8 halfYMax = uint8(480 / gridSize - 1);
            uint8 halfYCnt = uint8(480 / gridSize);

            _calcPath(R, grid, xMin, xMax, 0, halfYMax, maxStep, minSeg);

            uint256[120] memory grid2;
            _calcPath(R, grid2, xMin, xMax, 0, halfYMax, maxStep, minSeg);

            uint8 mid = xMax + 1;
            uint8 w = xMax - xMin;

            for (uint8 j = 0; j < halfYCnt; j++) {
                uint256 srcRow = grid2[j];
                if (srcRow == 0) continue;
                for (uint8 i = xMin; i <= xMax; i++) {
                    if ((srcRow >> i) & 1 != 0) {
                        grid[j] |= uint256(1) << (mid + (w - (i - xMin)));
                    }
                }
            }

            for (uint8 j = 0; j < halfYCnt; j++) {
                grid[gridCount - 1 - j] |= grid[j];
            }
        }

        uint8 maxCoord = gridCount - 1;
        bool touchLeft   = false;
        bool touchRight  = false;
        bool touchTop    = grid[0] != 0;
        bool touchBottom = grid[maxCoord] != 0;

        for (uint8 j = 0; j < gridCount; j++) {
            if (grid[j] == 0) continue;
            if ((grid[j] >> 0) & 1 != 0)        touchLeft  = true;
            if ((grid[j] >> maxCoord) & 1 != 0) touchRight = true;
        }

        uint8 edgesHit = 0;
        if (touchTop)    edgesHit++;
        if (touchBottom) edgesHit++;
        if (touchLeft)   edgesHit++;
        if (touchRight)  edgesHit++;

        bool corner = (touchTop && touchLeft) || (touchTop && touchRight) ||
                      (touchBottom && touchLeft) || (touchBottom && touchRight);

        uint8 edgeTouch;
        if (edgesHit == 0) edgeTouch = 0;
        else if (edgesHit == 1) edgeTouch = 1;
        else if (edgesHit == 2 && corner) edgeTouch = 2;
        else if (edgesHit == 2 && touchLeft && touchRight) edgeTouch = 3;
        else if (edgesHit == 2 && touchTop && touchBottom) edgeTouch = 4;
        else if (edgesHit == 3) edgeTouch = 5;
        else edgeTouch = 6;

        return (_toPath(grid, gridCount, gridSize), edgeTouch);
    }

    struct Bounds {
        uint8 maxDxPos;
        uint8 maxDxNeg;
        uint8 maxDyPos;
        uint8 maxDyNeg;
        uint8 maxStep;
    }

    function _calcPath(
        PRNGLib.State memory R,
        uint256[120] memory g,
        uint8 xMin, uint8 xMax,
        uint8 yMin, uint8 yMax,
        uint8 maxStep, uint8 minSeg
    ) private pure {
        uint8 x = uint8(R.nextRange(uint32(xMax - xMin + 1))) + xMin;
        uint8 y = uint8(R.nextRange(uint32(yMax - yMin + 1))) + yMin;

        g[y] |= uint256(1) << x;

        Bounds memory b;
        b.maxStep = maxStep;

        for (uint8 seg = 0; seg <= 50; seg++) {
            b.maxDxPos = xMax - x;
            b.maxDxNeg = x - xMin;
            b.maxDyPos = yMax - y;
            b.maxDyNeg = y - yMin;

            uint16 cnt = _countMovesO1(b);
            if (cnt == 0) break;

            uint16 pick = uint16(R.nextRange(cnt));
            (int16 dx, int16 dy, uint8 ns) = _pickMoveO1(pick, b);

            for (uint8 s = 1; s <= ns; s++) {
                int16 dns = int16(uint16(ns));
                int16 rawX = dx * int16(uint16(s));
                int16 rawY = dy * int16(uint16(s));

                int16 rx = rawX >= 0
                    ? (rawX + dns / 2) / dns
                    : -((-rawX + dns / 2) / dns);
                int16 ry = rawY >= 0
                    ? (rawY + dns / 2) / dns
                    : -((-rawY + dns / 2) / dns);

                uint8 setX = uint8(uint16(int16(uint16(x)) + rx));
                uint8 setY = uint8(uint16(int16(uint16(y)) + ry));

                g[setY] |= uint256(1) << setX;
            }

            x = uint8(uint16(int16(uint16(x)) + dx));
            y = uint8(uint16(int16(uint16(y)) + dy));

            bool edge = x == xMin || x == xMax || y == yMin || y == yMax;
            if (seg + 1 >= minSeg && edge) break;
        }
    }

    function _countMovesO1(Bounds memory b) private pure returns (uint16 cnt) {
        uint8 lim0 = _min3(b.maxStep, b.maxDxPos, b.maxDyPos);
        uint8 lim1 = _min3(b.maxStep, b.maxDxPos, b.maxDyNeg);
        uint8 lim2 = _min3(b.maxStep, b.maxDxNeg, b.maxDyPos);
        uint8 lim3 = _min3(b.maxStep, b.maxDxNeg, b.maxDyNeg);
        uint8 lim4 = _min2(b.maxStep, b.maxDxPos);
        uint8 lim5 = _min2(b.maxStep, b.maxDxNeg);
        uint8 lim6 = _min2(b.maxStep, b.maxDyPos);
        uint8 lim7 = _min2(b.maxStep, b.maxDyNeg);

        cnt = uint16(lim0) + uint16(lim1) + uint16(lim2) + uint16(lim3)
            + uint16(lim4) + uint16(lim5) + uint16(lim6) + uint16(lim7);
    }

    function _pickMoveO1(uint16 pick, Bounds memory b) private pure returns (int16 dx, int16 dy, uint8 ns) {
        uint8 lim0 = _min3(b.maxStep, b.maxDxPos, b.maxDyPos);
        uint8 lim1 = _min3(b.maxStep, b.maxDxPos, b.maxDyNeg);
        uint8 lim2 = _min3(b.maxStep, b.maxDxNeg, b.maxDyPos);
        uint8 lim3 = _min3(b.maxStep, b.maxDxNeg, b.maxDyNeg);
        uint8 lim4 = _min2(b.maxStep, b.maxDxPos);
        uint8 lim5 = _min2(b.maxStep, b.maxDxNeg);
        uint8 lim6 = _min2(b.maxStep, b.maxDyPos);
        uint8 lim7 = _min2(b.maxStep, b.maxDyNeg);

        uint16 cumulative = 0;

        for (uint8 s = 1; s <= b.maxStep; s++) {
            uint8 validCount = 0;
            if (s <= lim0) validCount++;
            if (s <= lim1) validCount++;
            if (s <= lim2) validCount++;
            if (s <= lim3) validCount++;
            if (s <= lim4) validCount++;
            if (s <= lim5) validCount++;
            if (s <= lim6) validCount++;
            if (s <= lim7) validCount++;

            if (validCount == 0) break;

            if (pick < cumulative + validCount) {
                uint8 localPick = uint8(pick - cumulative);

                if (s <= lim0) {
                    if (localPick == 0) return (int16(uint16(s)), int16(uint16(s)), s);
                    localPick--;
                }
                if (s <= lim1) {
                    if (localPick == 0) return (int16(uint16(s)), -int16(uint16(s)), s);
                    localPick--;
                }
                if (s <= lim2) {
                    if (localPick == 0) return (-int16(uint16(s)), int16(uint16(s)), s);
                    localPick--;
                }
                if (s <= lim3) {
                    if (localPick == 0) return (-int16(uint16(s)), -int16(uint16(s)), s);
                    localPick--;
                }
                if (s <= lim4) {
                    if (localPick == 0) return (int16(uint16(s)), 0, s);
                    localPick--;
                }
                if (s <= lim5) {
                    if (localPick == 0) return (-int16(uint16(s)), 0, s);
                    localPick--;
                }
                if (s <= lim6) {
                    if (localPick == 0) return (0, int16(uint16(s)), s);
                    localPick--;
                }
                if (s <= lim7) {
                    if (localPick == 0) return (0, -int16(uint16(s)), s);
                    localPick--;
                }
            }

            cumulative += validCount;
        }

        return (0, 0, 0);
    }

    function _min2(uint8 a, uint8 b) private pure returns (uint8) {
        return a < b ? a : b;
    }

    function _min3(uint8 a, uint8 b, uint8 c) private pure returns (uint8) {
        uint8 m = a < b ? a : b;
        return m < c ? m : c;
    }

    function _mirX(uint256[120] memory g, uint8 xMin, uint8 xMax, uint8 yCnt) private pure {
        uint8 mid = xMax + 1;
        uint8 w = xMax - xMin;
        for (uint8 j = 0; j < yCnt; j++) {
            uint256 row = g[j];
            if (row == 0) continue;
            uint256 newBits;
            for (uint8 i = xMin; i <= xMax; i++) {
                if ((row >> i) & 1 != 0) {
                    newBits |= uint256(1) << (mid + (w - (i - xMin)));
                }
            }
            g[j] |= newBits;
        }
    }

    function _mirY(uint256[120] memory g, uint8 xMin, uint8 xMax, uint8 yMin, uint8 yMax) private pure {
        uint8 mid = yMax + 1;
        uint8 h = yMax - yMin;
        uint256 colMask = ((uint256(1) << (xMax - xMin + 1)) - 1) << xMin;
        for (uint8 j = yMin; j <= yMax; j++) {
            uint8 targetJ = mid + (h - (j - yMin));
            g[targetJ] |= g[j] & colMask;
        }
    }

    function _toPath(
        uint256[120] memory g,
        uint8 cnt,
        uint16 size
    ) private pure returns (string memory) {
        bytes memory p = new bytes(32000);
        uint256 ptr;
        assembly { ptr := add(p, 32) }

        for (uint8 j = 0; j < cnt; j++) {
            uint256 row = g[j];
            if (row == 0) continue;

            uint8 i = 0;
            while (i < cnt) {
                if ((row >> i) & 1 == 0) {
                    i++;
                    continue;
                }

                uint8 iStart = i;
                while (i < cnt && ((row >> i) & 1 != 0)) {
                    i++;
                }
                uint8 runWidth = i - iStart;

                uint256 mask = ((uint256(1) << runWidth) - 1) << iStart;

                uint8 jEnd = j + 1;
                while (jEnd < cnt && (g[jEnd] & mask) == mask) {
                    jEnd++;
                }

                uint256 clearMask = ~mask;
                for (uint8 jj = j; jj < jEnd; jj++) {
                    g[jj] &= clearMask;
                }

                row &= clearMask;

                uint256 x = uint256(iStart) * uint256(size);
                uint256 y = uint256(j) * uint256(size);
                uint256 w = uint256(runWidth) * uint256(size);
                uint256 h = uint256(jEnd - j) * uint256(size);
                ptr = _sq(ptr, x, y, w, h);
            }
        }

        assembly { mstore(p, sub(ptr, add(p, 32))) }
        return string(p);
    }

    function _sq(uint256 ptr, uint256 x, uint256 y, uint256 w, uint256 h) private pure returns (uint256) {
        assembly { mstore8(ptr, 77) ptr := add(ptr, 1) }
        ptr = _num(ptr, x);
        assembly { mstore8(ptr, 32) ptr := add(ptr, 1) }
        ptr = _num(ptr, y);
        assembly { mstore8(ptr, 104) ptr := add(ptr, 1) }
        ptr = _num(ptr, w);
        assembly { mstore8(ptr, 118) ptr := add(ptr, 1) }
        ptr = _num(ptr, h);
        assembly {
            mstore8(ptr, 104)
            mstore8(add(ptr, 1), 45)
            ptr := add(ptr, 2)
        }
        ptr = _num(ptr, w);
        assembly { mstore8(ptr, 122) ptr := add(ptr, 1) }
        return ptr;
    }

    function _num(uint256 ptr, uint256 val) private pure returns (uint256) {
        if (val == 0) {
            assembly { mstore8(ptr, 48) }
            return ptr + 1;
        }

        uint256 end = ptr;
        uint256 t = val;

        while (t != 0) {
            end++;
            t /= 10;
        }

        assembly {
            let p := sub(end, 1)
            for { } gt(val, 0) { } {
                mstore8(p, add(mod(val, 10), 48))
                p := sub(p, 1)
                val := div(val, 10)
            }
        }

        return end;
    }
}