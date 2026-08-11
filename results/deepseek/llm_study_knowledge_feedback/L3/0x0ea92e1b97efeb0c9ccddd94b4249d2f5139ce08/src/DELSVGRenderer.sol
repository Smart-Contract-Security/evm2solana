// SPDX-License-Identifier: MIT

import {IDELSVGRenderer, TokenStateView} from "./IDELRenderer.sol";
import {IDELDataStore} from "./DELDataStore.sol";
import {IDELTuner} from "./DELTuner.sol";

contract DELSVGRenderer is IDELSVGRenderer {
    uint64 internal constant PALETTE_BYTES = 76;
    uint64 internal constant MAX_VOIDLING  = 12;

    bytes internal constant SPHERE_DATA =
        hex"00000000007788999aaa000000000000000006677888999aaabbb000000000000556677788999aaabbbbb00000000345566677888999aaabbbbbb0000034445566777888999aaabbbbbb0002334455566777888999aaabbbbbb0023344455566777888999aaaabbbb022233444555667778889999aaaaaba1223334445556667778889999aaaaa122233344455566677788889999999112223334445555666777888899999011222333344455566667778888880011122223334445555666677777770001112222333344455556666677700000111122223333444555556666000000001111222233334444555500000000000011112222333334440000000000000000011122222230000000000";

    uint64 internal constant SPHERE_COLS   = 30;
    uint64 internal constant SPHERE_ROWS   = 18;
    uint64 internal constant SPHERE_STEP_X = 14;
    uint64 internal constant SPHERE_STEP_Y = 24;
    uint64 internal constant SPHERE_X0     = 530;
    uint64 internal constant SPHERE_Y0     = 70;
    uint64 internal constant SPHERE_SHADES = 11;

    function svg(uint64 tokenId, TokenStateView calldata v, address dataStoreAddr, address tunerAddr)
        external
        view
        returns (bytes memory)
    {
        IDELDataStore dataStore = IDELDataStore(dataStoreAddr);
        bytes memory palettes = dataStore.palettes();
        bytes memory charSets = dataStore.charSets();
        bytes memory charOffs = dataStore.charSetsOffsets();
        int32[21] memory eff  = IDELTuner(tunerAddr).effectiveFields(tokenId);

        string memory bg = _namedColor(palettes, v.paletteIdx, 0);
        string memory tx = _namedColor(palettes, v.paletteIdx, 4);
        string memory ac = _namedColor(palettes, v.paletteIdx, 2);
        string memory palette = _charSet(charSets, charOffs, v.charSetIdx);

        bytes memory buf;
        buf = _concat(buf, '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000" font-family="\'Courier New\', Courier, monospace" font-size="22">');
        buf = _concat(buf, '<rect width="1000" height="1000" fill="');
        buf = _concat(buf, bytes(bg));
        buf = _concat(buf, '"/>');

        buf = _concat(buf, '<text x="54" y="70" fill="');
        buf = _concat(buf, bytes(tx));
        buf = _concat(buf, '">DEL <tspan fill="');
        buf = _concat(buf, bytes(ac));
        buf = _concat(buf, '">#');
        buf = _concat(buf, bytes(_toString(tokenId)));
        if (v.tuned) {
            buf = _concat(buf, " [TUNED]");
        }
        buf = _concat(buf, "</tspan></text>");
        buf = _concat(buf, '<text x="54" y="105" fill="');
        buf = _concat(buf, bytes(tx));
        buf = _concat(buf, '">OWNER: <tspan fill="');
        buf = _concat(buf, bytes(ac));
        buf = _concat(buf, '">');
        buf = _concat(buf, _shortAddr(v.owner));
        buf = _concat(buf, "</tspan></text>");
        if (v.tuned) {
            address lastBy = IDELTuner(tunerAddr).lastTunedBy(tokenId);
            buf = _concat(buf, '<text x="54" y="140" fill="');
            buf = _concat(buf, bytes(tx));
            buf = _concat(buf, '">TUNED BY: <tspan fill="');
            buf = _concat(buf, bytes(ac));
            buf = _concat(buf, '">');
            buf = _concat(buf, _shortAddr(lastBy));
            buf = _concat(buf, "</tspan></text>");
        }

        buf = _concat(buf, '<text x="54" y="235" fill="');
        buf = _concat(buf, bytes(tx));
        buf = _concat(buf, '">COLOUR PALETTE: <tspan fill="');
        buf = _concat(buf, bytes(ac));
        buf = _concat(buf, '">');
        buf = _concat(buf, bytes(_toString(uint64(v.paletteIdx) + 1)));
        buf = _concat(buf, "</tspan></text>");
        buf = _concat(buf, '<text x="54" y="270" fill="');
        buf = _concat(buf, bytes(tx));
        buf = _concat(buf, '">CHARACTER SET: <tspan fill="');
        buf = _concat(buf, bytes(ac));
        buf = _concat(buf, '">');
        buf = _concat(buf, bytes(_toString(uint64(v.charSetIdx) + 1)));
        buf = _concat(buf, "</tspan></text>");
        buf = _concat(buf, '<text x="54" y="305" fill="');
        buf = _concat(buf, bytes(tx));
        buf = _concat(buf, '">BEHAVIOUR SET: <tspan fill="');
        buf = _concat(buf, bytes(ac));
        buf = _concat(buf, '">');
        buf = _concat(buf, bytes(_toString(uint64(v.behaviourIdx) + 1)));
        buf = _concat(buf, "</tspan></text>");

        buf = _sphere(buf, palettes, v.paletteIdx, palette);

        buf = _row(buf, 440, "BASE RADIUS",         _fixI32(eff[0]),  tx, ac);
        buf = _row(buf, 475, "ASPECT RATIO",        _fixI32(eff[1]),  tx, ac);
        buf = _row(buf, 510, "STEP SIZE",           _fixI32(eff[2]),  tx, ac);
        buf = _row(buf, 545, "MOVE SPEED",          _fixI32(eff[3]),  tx, ac);
        buf = _row(buf, 580, "MAX MOVE DISTANCE",   _fixI32(eff[4]),  tx, ac);
        buf = _row2(buf, 615, "X/Y BIAS",           _fixI32(eff[5]),  _fixI32(eff[6]),  tx, ac);
        buf = _row2(buf, 650, "MIN/MAX ROTATION SPEED", _fixI32(eff[7]), _fixI32(eff[8]), tx, ac);
        buf = _row(buf, 685, "ROTATION SMOOTHNESS", _fixI32(eff[9]),  tx, ac);
        buf = _row(buf, 720, "MAX ROTATION ANGLE",  _fixI32(eff[10]), tx, ac);
        buf = _row2(buf, 755, "BASE/EXTRA DEFORM STRENGTH", _fixI32(eff[11]), _fixI32(eff[12]), tx, ac);
        buf = _row3(buf, 790, "DEFORM FREQUENCY/COMPLEXITY/SMOOTHNESS",
            _fixI32(eff[13]), _fixI32(eff[14]), _fixI32(eff[15]), tx, ac);
        buf = _row(buf, 825, "DRIPPINESS",          _fixI32(eff[16]), tx, ac);
        buf = _row(buf, 860, "TIME SPEED",          _fixI32(eff[17]), tx, ac);
        buf = _row2(buf, 895, "PERSPECTIVE DISTANCE/STRENGTH", _fixI32(eff[18]), _fixI32(eff[19]), tx, ac);
        buf = _row(buf, 930, "BEHAVIOR CHANGE TIME",_fixI32(eff[20]), tx, ac);

        buf = _concat(buf, "</svg>");
        return buf;
    }

    function _sphere(
        bytes memory buf,
        bytes memory palettes,
        uint8 paletteIdx,
        string memory palette
    ) internal pure returns (bytes memory) {
        bytes[11] memory tail;
        bytes memory paletteBytes = bytes(palette);
        uint64[11] memory charOff;
        uint64[11] memory charLen;
        (charOff, charLen) = _scanCharOffsets(paletteBytes);
        for (uint64 s = 0; s < 11; s++) {
            bytes memory t;
            t = _concat(t, '" fill="');
            t = _concat(t, bytes(_toHexColor(_voidlingColor(palettes, paletteIdx, s))));
            t = _concat(t, '">');
            t = _concat(t, _xmlEscape(_sliceFromOffset(paletteBytes, charOff[s], charLen[s])));
            t = _concat(t, '</tspan>');
            tail[s] = t;
        }

        bytes[30] memory xStr;
        for (uint64 c = 0; c < 30; c++) {
            xStr[c] = bytes(_toString(SPHERE_X0 + c * SPHERE_STEP_X));
        }

        bytes memory data = SPHERE_DATA;

        for (uint64 row = 0; row < SPHERE_ROWS; row++) {
            bool rowOpened;
            uint64 rowNibBase = row * SPHERE_COLS;
            for (uint64 col = 0; col < SPHERE_COLS; col++) {
                uint64 nibIdx = rowNibBase + col;
                uint8 packed = uint8(data[nibIdx >> 1]);
                uint8 nibble = (nibIdx & 1) == 0 ? (packed >> 4) : (packed & 0x0f);
                if (nibble == 0) continue;
                if (!rowOpened) {
                    buf = _concat(buf, '<text y="');
                    buf = _concat(buf, bytes(_toString(SPHERE_Y0 + row * SPHERE_STEP_Y)));
                    buf = _concat(buf, '">');
                    rowOpened = true;
                }
                buf = _concat(buf, '<tspan x="');
                buf = _concat(buf, xStr[col]);
                buf = _concat(buf, tail[nibble - 1]);
            }
            if (rowOpened) {
                buf = _concat(buf, "</text>");
            }
        }
        return buf;
    }

    function _scanCharOffsets(
        bytes memory palette
    ) internal pure returns (uint64[11] memory offsets, uint64[11] memory lens) {
        uint64 i;
        uint64 chIdx;
        while (i < palette.length && chIdx < 11) {
            uint64 cl = _utf8Len(uint8(palette[i]));
            offsets[chIdx] = i;
            lens[chIdx] = cl;
            i += cl;
            chIdx += 1;
        }
    }

    function _utf8Len(uint8 b) internal pure returns (uint64) {
        if (b < 0x80) return 1;
        if (b < 0xC0) return 1;
        if (b < 0xE0) return 2;
        if (b < 0xF0) return 3;
        return 4;
    }

    function _sliceFromOffset(bytes memory src, uint64 offset, uint64 len) internal pure returns (bytes memory out) {
        out = new bytes(len);
        for (uint64 i = 0; i < len; i++) {
            out[i] = src[offset + i];
        }
    }

    function _row(
        bytes memory buf,
        uint64 y,
        string memory label,
        string memory val,
        string memory tx_,
        string memory ac
    ) internal pure returns (bytes memory) {
        buf = _concat(buf, '<text x="54" y="');
        buf = _concat(buf, bytes(_toString(y)));
        buf = _concat(buf, '" fill="');
        buf = _concat(buf, bytes(tx_));
        buf = _concat(buf, '">');
        buf = _concat(buf, bytes(label));
        buf = _concat(buf, ': <tspan fill="');
        buf = _concat(buf, bytes(ac));
        buf = _concat(buf, '">');
        buf = _concat(buf, bytes(val));
        buf = _concat(buf, "</tspan></text>");
        return buf;
    }

    function _row2(
        bytes memory buf,
        uint64 y,
        string memory label,
        string memory a,
        string memory bb,
        string memory tx_,
        string memory ac
    ) internal pure returns (bytes memory) {
        buf = _concat(buf, '<text x="54" y="');
        buf = _concat(buf, bytes(_toString(y)));
        buf = _concat(buf, '" fill="');
        buf = _concat(buf, bytes(tx_));
        buf = _concat(buf, '">');
        buf = _concat(buf, bytes(label));
        buf = _concat(buf, ': <tspan fill="');
        buf = _concat(buf, bytes(ac));
        buf = _concat(buf, '">');
        buf = _concat(buf, bytes(a));
        buf = _concat(buf, "/");
        buf = _concat(buf, bytes(bb));
        buf = _concat(buf, "</tspan></text>");
        return buf;
    }

    function _row3(
        bytes memory buf,
        uint64 y,
        string memory label,
        string memory a,
        string memory bb,
        string memory c,
        string memory tx_,
        string memory ac
    ) internal pure returns (bytes memory) {
        buf = _concat(buf, '<text x="54" y="');
        buf = _concat(buf, bytes(_toString(y)));
        buf = _concat(buf, '" fill="');
        buf = _concat(buf, bytes(tx_));
        buf = _concat(buf, '">');
        buf = _concat(buf, bytes(label));
        buf = _concat(buf, ': <tspan fill="');
        buf = _concat(buf, bytes(ac));
        buf = _concat(buf, '">');
        buf = _concat(buf, bytes(a));
        buf = _concat(buf, "/");
        buf = _concat(buf, bytes(bb));
        buf = _concat(buf, "/");
        buf = _concat(buf, bytes(c));
        buf = _concat(buf, "</tspan></text>");
        return buf;
    }

    function _shortAddr(address a) internal pure returns (bytes memory out) {
        bytes memory full = bytes(_toHexString(a));
        out = new bytes(14);
        for (uint64 i = 0; i < 14; i++) {
            out[i] = full[i];
        }
    }

    function _xmlEscape(bytes memory ch) internal pure returns (bytes memory) {
        if (ch.length == 1) {
            bytes1 c = ch[0];
            if (c == "<") return bytes("&lt;");
            if (c == ">") return bytes("&gt;");
            if (c == "&") return bytes("&amp;");
            if (c == "\"") return bytes("&quot;");
            if (c == "'") return bytes("&#39;");
        }
        return ch;
    }

    function _fixI32(int32 v) internal pure returns (string memory) {
        if (v < 0) {
            uint64 mag = uint64(-v);
            return _concat("-", _fix(mag));
        }
        return _fix(uint64(uint32(v)));
    }

    function _fix(uint64 v) internal pure returns (string memory) {
        uint64 whole = v / 1000;
        uint64 frac = v % 1000;
        string memory s = _toString(whole);
        if (frac == 0) return s;
        string memory f = _toString(frac);
        while (bytes(f).length < 3) {
            f = _concat("0", f);
        }
        return _concat(_concat(s, "."), f);
    }

    function _voidlingColor(bytes memory palettes, uint8 paletteIdx, uint64 charIdx) internal pure returns (bytes4) {
        uint64 off = uint64(paletteIdx) * PALETTE_BYTES + charIdx * 4;
        return bytes4(uint32(_readU32(palettes, off)));
    }

    function _namedColor(bytes memory palettes, uint8 paletteIdx, uint64 namedIdx) internal pure returns (string memory) {
        uint64 off = uint64(paletteIdx) * PALETTE_BYTES + MAX_VOIDLING * 4 + namedIdx * 4;
        return _toHexColor(bytes4(uint32(_readU32(palettes, off))));
    }

    function _toHexColor(bytes4 c) internal pure returns (string memory) {
        bytes memory hexChars = "0123456789abcdef";
        bytes memory result = new bytes(7);
        result[0] = '#';
        for (uint64 i = 0; i < 4; i++) {
            uint8 b = uint8(c[i]);
            result[1 + i * 2] = hexChars[b >> 4];
            result[2 + i * 2] = hexChars[b & 0x0f];
        }
        return string(result);
    }

    function _charSet(bytes memory charSets, bytes memory charOffs, uint8 idx) internal pure returns (string memory) {
        uint64 off = _readU16(charOffs, uint64(idx) * 2);
        return _readLengthPrefixed(charSets, off);
    }

    function _readU32(bytes memory data, uint64 off) internal pure returns (uint64) {
        uint64 v;
        v |= uint64(uint8(data[off])) << 24;
        v |= uint64(uint8(data[off + 1])) << 16;
        v |= uint64(uint8(data[off + 2])) << 8;
        v |= uint64(uint8(data[off + 3]));
        return v;
    }

    function _readU16(bytes memory data, uint64 off) internal pure returns (uint64) {
        uint64 v;
        v |= uint64(uint8(data[off])) << 8;
        v |= uint64(uint8(data[off + 1]));
        return v;
    }

    function _readLengthPrefixed(bytes memory data, uint64 off) internal pure returns (string memory) {
        uint64 len = _readU16(data, off);
        bytes memory result = new bytes(len);
        for (uint64 i = 0; i < len; i++) {
            result[i] = data[off + 2 + i];
        }
        return string(result);
    }

    function _concat(bytes memory a, bytes memory b) internal pure returns (bytes memory) {
        bytes memory result = new bytes(a.length + b.length);
        uint64 i;
        for (i = 0; i < a.length; i++) {
            result[i] = a[i];
        }
        for (uint64 j = 0; j < b.length; j++) {
            result[i + j] = b[j];
        }
        return result;
    }

    function _concat(string memory a, string memory b) internal pure returns (string memory) {
        bytes memory aBytes = bytes(a);
        bytes memory bBytes = bytes(b);
        bytes memory result = new bytes(aBytes.length + bBytes.length);
        uint64 i;
        for (i = 0; i < aBytes.length; i++) {
            result[i] = aBytes[i];
        }
        for (uint64 j = 0; j < bBytes.length; j++) {
            result[i + j] = bBytes[j];
        }
        return string(result);
    }

    function _toString(uint64 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint64 temp = value;
        uint64 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint64(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function _toHexString(address a) internal pure returns (string memory) {
        bytes memory addr = new bytes(32);
        // Manually store address bytes into the array without assembly
        uint64 addrUint = uint64(uint160(a));
        for (uint64 i = 0; i < 20; i++) {
            addr[12 + i] = bytes1(uint8((addrUint >> (8 * (19 - i))) & 0xff));
        }
        bytes memory hexChars = "0123456789abcdef";
        bytes memory result = new bytes(42);
        result[0] = '0';
        result[1] = 'x';
        for (uint64 i = 0; i < 20; i++) {
            result[2 + i * 2] = hexChars[uint8(addr[12 + i] >> 4)];
            result[3 + i * 2] = hexChars[uint8(addr[12 + i] & 0x0f)];
        }
        return string(result);
    }
}