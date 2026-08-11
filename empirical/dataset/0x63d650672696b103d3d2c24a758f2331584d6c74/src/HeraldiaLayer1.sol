// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

library HeraldiaLayer1 {
    struct Ctx {
        uint16 grid;
        uint16 cols;
        uint8 bgTCase;
        uint8 divisor;
        uint8 evenodd;
    }

    function generatePath(
        uint32 layer1ValueRand,
        uint32 choiceRand,
        uint32 divisorRand,
        uint32 evenoddRand,
        uint8 bgTSize,
        uint8 bgTCase
    ) internal pure returns (string memory) {
        bytes memory out = new bytes(40000);
        uint256 ptr;
        assembly {
            ptr := add(out, 32)
        }

        Ctx memory c;
        c.grid = 960 / uint16(bgTSize);
        c.cols = 960 / c.grid;
        c.bgTCase = bgTCase;
        c.divisor = uint8(divisorRand);
        if (c.divisor == 0) c.divisor = 1;
        c.evenodd = uint8(evenoddRand) & 1;

        uint8 layer1Value = uint8(layer1ValueRand) + 1;
        uint8 choice = uint8(choiceRand);

        uint16 clipX0 = 0;
        uint16 clipX1 = 960;
        uint16 clipY0 = 0;
        uint16 clipY1 = 960;
        
        uint16 clipX0b = 0;
        uint16 clipX1b = 0;
        uint16 clipY0b = 0;
        uint16 clipY1b = 0;

        if (layer1Value == 2) {
            if (choice % 2 == 0) { clipX1 = 480; }
            else { clipX0 = 480; }
        } else if (layer1Value == 3) {
            if (choice % 2 == 0) { clipY1 = 480; }
            else { clipY0 = 480; }
        } else if (layer1Value == 4) {
            uint8 m = choice % 4;
            if (m == 0) { clipY1 = 320; }
            else if (m == 1) { clipY0 = 320; clipY1 = 640; }
            else if (m == 2) { clipY0 = 640; }
            else { clipY1 = 320; clipY0b = 640; clipY1b = 960; }
        } else if (layer1Value == 5) {
            uint8 m = choice % 6;
            if (m == 0) { clipX1 = 480; clipY1 = 480; }
            else if (m == 1) { clipX0 = 480; clipY1 = 480; }
            else if (m == 2) { clipX1 = 480; clipY0 = 480; }
            else if (m == 3) { clipX0 = 480; clipY0 = 480; }
            else if (m == 4) { 
                clipX1 = 480; clipY1 = 480;
                clipX0b = 480; clipX1b = 960; clipY0b = 480; clipY1b = 960;
            }
            else { 
                clipX0 = 480; clipY1 = 480;
                clipX0b = 0; clipX1b = 480; clipY0b = 480; clipY1b = 960;
            }
        }

        ptr = _renderRegion(ptr, c, clipX0, clipX1, clipY0, clipY1);
        
        if (clipY1b > clipY0b) {
            ptr = _renderRegion(ptr, c, clipX0b, clipX1b, clipY0b, clipY1b);
        }

        assembly {
            mstore(out, sub(ptr, add(out, 32)))
        }
        return string(out);
    }

    function _renderRegion(
        uint256 ptr,
        Ctx memory c,
        uint16 clipX0,
        uint16 clipX1,
        uint16 clipY0,
        uint16 clipY1
    ) private pure returns (uint256) {
        if (c.bgTCase == 1) {
            return _genSolid(ptr, clipX0, clipX1, clipY0, clipY1);
        }
        if (c.bgTCase == 2) {
            return _genHorizontalStripes(ptr, c, clipX0, clipX1, clipY0, clipY1);
        }
        if (c.bgTCase == 3) {
            return _genVerticalStripes(ptr, c, clipX0, clipX1, clipY0, clipY1);
        }
        if (c.bgTCase == 4) {
            return _genDiagonal(ptr, c, clipX0, clipX1, clipY0, clipY1);
        }
        if (c.bgTCase == 5) {
            return _genGrid(ptr, c, clipX0, clipX1, clipY0, clipY1);
        }
        if (c.bgTCase == 6) {
            return _genDots(ptr, c, clipX0, clipX1, clipY0, clipY1);
        }
        return ptr;
    }

    function _genSolid(
        uint256 ptr,
        uint16 clipX0,
        uint16 clipX1,
        uint16 clipY0,
        uint16 clipY1
    ) private pure returns (uint256) {
        return _writeRect(ptr, clipX0, clipY0, clipX1 - clipX0, clipY1 - clipY0);
    }

    function _genHorizontalStripes(
        uint256 ptr,
        Ctx memory c,
        uint16 clipX0,
        uint16 clipX1,
        uint16 clipY0,
        uint16 clipY1
    ) private pure returns (uint256) {
        unchecked {
            uint16 jStart = clipY0 / c.grid;
            uint16 jEnd = (clipY1 + c.grid - 1) / c.grid;
            if (jEnd > c.cols) jEnd = c.cols;
            
            uint16 j = jStart;
            while (j < jEnd) {
                if (j % c.divisor != c.evenodd) {
                    j++;
                    continue;
                }
                
                uint16 j0 = j;
                j++;
                while (j < jEnd && (j % c.divisor == c.evenodd)) {
                    j++;
                }
                
                uint16 y0 = j0 * c.grid;
                uint16 y1 = j * c.grid;
                if (y0 < clipY0) y0 = clipY0;
                if (y1 > clipY1) y1 = clipY1;
                
                if (y1 > y0) {
                    ptr = _writeRect(ptr, clipX0, y0, clipX1 - clipX0, y1 - y0);
                }
            }
        }
        return ptr;
    }

    function _genVerticalStripes(
        uint256 ptr,
        Ctx memory c,
        uint16 clipX0,
        uint16 clipX1,
        uint16 clipY0,
        uint16 clipY1
    ) private pure returns (uint256) {
        unchecked {
            uint16 iStart = clipX0 / c.grid;
            uint16 iEnd = (clipX1 + c.grid - 1) / c.grid;
            if (iEnd > c.cols) iEnd = c.cols;
            
            uint16 i = iStart;
            while (i < iEnd) {
                if (i % c.divisor != c.evenodd) {
                    i++;
                    continue;
                }
                
                uint16 i0 = i;
                i++;
                while (i < iEnd && (i % c.divisor == c.evenodd)) {
                    i++;
                }
                
                uint16 x0 = i0 * c.grid;
                uint16 x1 = i * c.grid;
                if (x0 < clipX0) x0 = clipX0;
                if (x1 > clipX1) x1 = clipX1;
                
                if (x1 > x0) {
                    ptr = _writeRect(ptr, x0, clipY0, x1 - x0, clipY1 - clipY0);
                }
            }
        }
        return ptr;
    }

    function _genDiagonal(
        uint256 ptr,
        Ctx memory c,
        uint16 clipX0,
        uint16 clipX1,
        uint16 clipY0,
        uint16 clipY1
    ) private pure returns (uint256) {
        unchecked {
            uint16 jStart = clipY0 / c.grid;
            uint16 jEnd = (clipY1 + c.grid - 1) / c.grid;
            if (jEnd > c.cols) jEnd = c.cols;
            
            uint16 iStart = clipX0 / c.grid;
            uint16 iEnd = (clipX1 + c.grid - 1) / c.grid;
            if (iEnd > c.cols) iEnd = c.cols;
            
            for (uint16 j = jStart; j < jEnd; j++) {
                uint16 y0 = j * c.grid;
                uint16 y1 = y0 + c.grid;
                if (y0 < clipY0) y0 = clipY0;
                if (y1 > clipY1) y1 = clipY1;
                if (y1 <= y0) continue;
                
                uint16 i = iStart;
                while (i < iEnd) {
                    int16 patternValue = c.evenodd == 0
                        ? int16(uint16(i)) - int16(uint16(j))
                        : int16(uint16(i)) + int16(uint16(j));
                    int16 modv = patternValue % int16(uint16(c.divisor));
                    if (modv < 0) modv += int16(uint16(c.divisor));
                    
                    if (modv != 0) {
                        i++;
                        continue;
                    }
                    
                    uint16 i0 = i;
                    i++;
                    
                    while (i < iEnd) {
                        int16 pv = c.evenodd == 0
                            ? int16(uint16(i)) - int16(uint16(j))
                            : int16(uint16(i)) + int16(uint16(j));
                        int16 mv = pv % int16(uint16(c.divisor));
                        if (mv < 0) mv += int16(uint16(c.divisor));
                        if (mv != 0) break;
                        i++;
                    }
                    
                    uint16 x0 = i0 * c.grid;
                    uint16 x1 = i * c.grid;
                    if (x0 < clipX0) x0 = clipX0;
                    if (x1 > clipX1) x1 = clipX1;
                    
                    if (x1 > x0) {
                        ptr = _writeRect(ptr, x0, y0, x1 - x0, y1 - y0);
                    }
                }
            }
        }
        return ptr;
    }

    function _genGrid(
        uint256 ptr,
        Ctx memory c,
        uint16 clipX0,
        uint16 clipX1,
        uint16 clipY0,
        uint16 clipY1
    ) private pure returns (uint256) {
        unchecked {
            uint16 jStart = clipY0 / c.grid;
            uint16 jEnd = (clipY1 + c.grid - 1) / c.grid;
            if (jEnd > c.cols) jEnd = c.cols;
            
            uint16 iStart = clipX0 / c.grid;
            uint16 iEnd = (clipX1 + c.grid - 1) / c.grid;
            if (iEnd > c.cols) iEnd = c.cols;
            
            for (uint16 j = jStart; j < jEnd; j++) {
                bool hLine = (j % c.divisor) == c.evenodd;
                
                uint16 y0 = j * c.grid;
                uint16 y1 = y0 + c.grid;
                if (y0 < clipY0) y0 = clipY0;
                if (y1 > clipY1) y1 = clipY1;
                if (y1 <= y0) continue;
                
                if (hLine) {
                    ptr = _writeRect(ptr, clipX0, y0, clipX1 - clipX0, y1 - y0);
                } else {
                    uint16 i = iStart;
                    while (i < iEnd) {
                        if (i % c.divisor != c.evenodd) {
                            i++;
                            continue;
                        }
                        
                        uint16 i0 = i;
                        i++;
                        while (i < iEnd && (i % c.divisor == c.evenodd)) {
                            i++;
                        }
                        
                        uint16 x0 = i0 * c.grid;
                        uint16 x1 = i * c.grid;
                        if (x0 < clipX0) x0 = clipX0;
                        if (x1 > clipX1) x1 = clipX1;
                        
                        if (x1 > x0) {
                            ptr = _writeRect(ptr, x0, y0, x1 - x0, y1 - y0);
                        }
                    }
                }
            }
        }
        return ptr;
    }

    function _genDots(
        uint256 ptr,
        Ctx memory c,
        uint16 clipX0,
        uint16 clipX1,
        uint16 clipY0,
        uint16 clipY1
    ) private pure returns (uint256) {
        unchecked {
            uint16 jStart = clipY0 / c.grid;
            uint16 jEnd = (clipY1 + c.grid - 1) / c.grid;
            if (jEnd > c.cols) jEnd = c.cols;
            
            uint16 iStart = clipX0 / c.grid;
            uint16 iEnd = (clipX1 + c.grid - 1) / c.grid;
            if (iEnd > c.cols) iEnd = c.cols;
            
            for (uint16 j = jStart; j < jEnd; j++) {
                if (j % c.divisor != c.evenodd) continue;
                
                uint16 y0 = j * c.grid;
                uint16 y1 = y0 + c.grid;
                if (y0 < clipY0) y0 = clipY0;
                if (y1 > clipY1) y1 = clipY1;
                if (y1 <= y0) continue;
                
                uint16 i = iStart;
                while (i < iEnd) {
                    if (i % c.divisor != c.evenodd) {
                        i++;
                        continue;
                    }
                    
                    uint16 i0 = i;
                    i++;
                    while (i < iEnd && (i % c.divisor == c.evenodd)) {
                        i++;
                    }
                    
                    uint16 x0 = i0 * c.grid;
                    uint16 x1 = i * c.grid;
                    if (x0 < clipX0) x0 = clipX0;
                    if (x1 > clipX1) x1 = clipX1;
                    
                    if (x1 > x0) {
                        ptr = _writeRect(ptr, x0, y0, x1 - x0, y1 - y0);
                    }
                }
            }
        }
        return ptr;
    }

    function _writeRect(
        uint256 ptr,
        uint16 x,
        uint16 y,
        uint16 w,
        uint16 h
    ) private pure returns (uint256) {
        assembly {
            mstore8(ptr, 0x4D)
            ptr := add(ptr, 1)
        }
        ptr = _wn(ptr, x);
        assembly {
            mstore8(ptr, 0x20)
            ptr := add(ptr, 1)
        }
        ptr = _wn(ptr, y);
        assembly {
            mstore8(ptr, 0x68)
            ptr := add(ptr, 1)
        }
        ptr = _wn(ptr, w);
        assembly {
            mstore8(ptr, 0x76)
            ptr := add(ptr, 1)
        }
        ptr = _wn(ptr, h);
        assembly {
            mstore8(ptr, 0x68)
            mstore8(add(ptr, 1), 0x2D)
            ptr := add(ptr, 2)
        }
        ptr = _wn(ptr, w);
        assembly {
            mstore8(ptr, 0x7A)
            ptr := add(ptr, 1)
        }
        return ptr;
    }

    function _wn(uint256 ptr, uint256 val) private pure returns (uint256) {
        assembly {
            switch val
            case 0 {
                mstore8(ptr, 48)
                ptr := add(ptr, 1)
            }
            default {
                switch lt(val, 10)
                case 1 {
                    mstore8(ptr, add(48, val))
                    ptr := add(ptr, 1)
                }
                default {
                    switch lt(val, 100)
                    case 1 {
                        let a := div(val, 10)
                        let b := mod(val, 10)
                        mstore8(ptr, add(48, a))
                        mstore8(add(ptr, 1), add(48, b))
                        ptr := add(ptr, 2)
                    }
                    default {
                        switch lt(val, 1000)
                        case 1 {
                            let a := div(val, 100)
                            let r := mod(val, 100)
                            let b := div(r, 10)
                            let c := mod(r, 10)
                            mstore8(ptr, add(48, a))
                            mstore8(add(ptr, 1), add(48, b))
                            mstore8(add(ptr, 2), add(48, c))
                            ptr := add(ptr, 3)
                        }
                        default {
                            let a := div(val, 1000)
                            let r1 := mod(val, 1000)
                            let b := div(r1, 100)
                            let r2 := mod(r1, 100)
                            let c := div(r2, 10)
                            let d := mod(r2, 10)
                            mstore8(ptr, add(48, a))
                            mstore8(add(ptr, 1), add(48, b))
                            mstore8(add(ptr, 2), add(48, c))
                            mstore8(add(ptr, 3), add(48, d))
                            ptr := add(ptr, 4)
                        }
                    }
                }
            }
        }
        return ptr;
    }
}