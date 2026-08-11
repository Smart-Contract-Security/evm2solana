// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IDELSVGRenderer {
    struct TokenStateView {
        uint8 paletteIdx;
        uint8 charSetIdx;
        uint8 behaviourIdx;
        bool tuned;
        address owner;
    }
}

interface IDELDataStore {
    function palettes() external view returns (bytes memory);
    function charSets() external view returns (bytes memory);
    function charSetsOffsets() external view returns (bytes memory);
}

interface IDELTuner {
    function effectiveFields(uint256 tokenId) external view returns (int32[21] memory);
    function lastTunedBy(uint256 tokenId) external view returns (address);
}

library LibString {
    function toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function toHexString(address addr) internal pure returns (string memory) {
        bytes memory buffer = new bytes(42);
        buffer[0] = '0';
        buffer[1] = 'x';
        for (uint256 i = 0; i < 20; i++) {
            uint8 b = uint8(uint160(addr) / (2**(8*(19 - i))));
            uint8 hi = b / 16;
            uint8 lo = b % 16;
            buffer[2 + i * 2] = _hexChar(hi);
            buffer[3 + i * 2] = _hexChar(lo);
        }
        return string(buffer);
    }

    function _hexChar(uint8 b) private pure returns (bytes1) {
        if (b < 10) return bytes1(uint8(b + 48));
        return bytes1(uint8(b + 87));
    }
}

library DynamicBufferLib {
    struct DynamicBuffer {
        bytes data;
    }

    function p(DynamicBuffer memory buf, string memory s) internal pure returns (DynamicBuffer memory) {
        buf.data = bytes.concat(buf.data, bytes(s));
        return buf;
    }

    function p(DynamicBuffer memory buf, bytes memory b) internal pure returns (DynamicBuffer memory) {
        buf.data = bytes.concat(buf.data, b);
        return buf;
    }
}

library RenderHelpers {
    function utf8Len(uint8 b) internal pure returns (uint256) {
        if (b < 0x80) return 1;
        if (b < 0xE0) return 2;
        if (b < 0xF0) return 3;
        return 4;
    }

    function readU32(bytes memory data, uint256 offset) internal pure returns (uint256) {
        uint256 val;
        for (uint256 i = 0; i < 4; i++) {
            val |= uint256(uint8(data[offset + i])) << (i * 8);
        }
        return val;
    }

    function readU16(bytes memory data, uint256 offset) internal pure returns (uint256) {
        uint256 val;
        for (uint256 i = 0; i < 2; i++) {
            val |= uint256(uint8(data[offset + i])) << (i * 8);
        }
        return val;
    }

    function readLengthPrefixed(bytes memory data, uint256 offset) internal pure returns (string memory) {
        uint256 len = readU16(data, offset);
        bytes memory str = new bytes(len);
        for (uint256 i; i < len; i++) {
            str[i] = data[offset + 2 + i];
        }
        return string(str);
    }

    function toHexColor(bytes4 color) internal pure returns (string memory) {
        bytes memory buf = new bytes(7);
        buf[0] = '#';
        bytes memory hexChars = "0123456789ABCDEF";
        for (uint256 i; i < 4; i++) {
            uint8 b = uint8(color[i]);
            buf[1 + i * 2] = hexChars[b >> 4];
            buf[2 + i * 2] = hexChars[b & 0x0F];
        }
        return string(buf);
    }

    function fix(uint256 v) internal pure returns (string memory) {
        uint256 intPart = v / 1000;
        uint256 fracPart = v % 1000;
        string memory intStr = LibString.toString(intPart);
        string memory fracStr = LibString.toString(fracPart);
        while (bytes(fracStr).length < 3) {
            fracStr = string.concat("0", fracStr);
        }
        return string.concat(intStr, ".", fracStr);
    }
}

contract DELSVGRenderer is IDELSVGRenderer {
    uint256 internal constant PALETTE_BYTES = 76;
    uint256 internal constant MAX_VOIDLING  = 12;

    bytes internal constant SPHERE_DATA =
        hex"00000000007788999aaa000000000000000006677888999aaabbb000000000000556677788999aaabbbbb00000000345566677888999aaabbbbbb0000034445566777888999aaabbbbbb0002334455566777888999aaabbbbbb0023344455566777888999aaaabbbb022233444555667778889999aaaaaba1223334445556667778889999aaaaa122233344455566677788889999999112223334445555666777888899999011222333344455566667778888880011122223334445555666677777770001112222333344455556666677700000111122223333444555556666000000001111222233334444555500000000000011112222333334440000000000000000011122222230000000000";

    uint256 internal constant SPHERE_COLS   = 30;
    uint256 internal constant SPHERE_ROWS   = 18;
    uint256 internal constant SPHERE_STEP_X = 14;
    uint256 internal constant SPHERE_STEP_Y = 24;
    uint256 internal constant SPHERE_X0     = 530;
    uint256 internal constant SPHERE_Y0     = 70;
    uint256 internal constant SPHERE_SHADES = 11;

    function svg(uint256 tokenId, IDELSVGRenderer.TokenStateView calldata v, address dataStoreAddr, address tunerAddr)
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

        DynamicBufferLib.DynamicBuffer memory buf;
        buf = DynamicBufferLib.p(buf, '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000" font-family="\'Courier New\', Courier, monospace" font-size="22">');
        buf = DynamicBufferLib.p(buf, '<rect width="1000" height="1000" fill="');
        buf = DynamicBufferLib.p(buf, bytes(bg));
        buf = DynamicBufferLib.p(buf, '"/>');

        buf = DynamicBufferLib.p(buf, '<text x="54" y="70" fill="');
        buf = DynamicBufferLib.p(buf, bytes(tx));
        buf = DynamicBufferLib.p(buf, '">DEL <tspan fill="');
        buf = DynamicBufferLib.p(buf, bytes(ac));
        buf = DynamicBufferLib.p(buf, '">#');
        buf = DynamicBufferLib.p(buf, bytes(LibString.toString(tokenId)));
        if (v.tuned) buf = DynamicBufferLib.p(buf, " [TUNED]");
        buf = DynamicBufferLib.p(buf, "</tspan></text>");
        buf = DynamicBufferLib.p(buf, '<text x="54" y="105" fill="');
        buf = DynamicBufferLib.p(buf, bytes(tx));
        buf = DynamicBufferLib.p(buf, '">OWNER: <tspan fill="');
        buf = DynamicBufferLib.p(buf, bytes(ac));
        buf = DynamicBufferLib.p(buf, '">');
        buf = DynamicBufferLib.p(buf, _shortAddr(v.owner));
        buf = DynamicBufferLib.p(buf, "</tspan></text>");
        if (v.tuned) {
            address lastBy = IDELTuner(tunerAddr).lastTunedBy(tokenId);
            buf = DynamicBufferLib.p(buf, '<text x="54" y="140" fill="');
            buf = DynamicBufferLib.p(buf, bytes(tx));
            buf = DynamicBufferLib.p(buf, '">TUNED BY: <tspan fill="');
            buf = DynamicBufferLib.p(buf, bytes(ac));
            buf = DynamicBufferLib.p(buf, '">');
            buf = DynamicBufferLib.p(buf, _shortAddr(lastBy));
            buf = DynamicBufferLib.p(buf, "</tspan></text>");
        }

        buf = DynamicBufferLib.p(buf, '<text x="54" y="235" fill="');
        buf = DynamicBufferLib.p(buf, bytes(tx));
        buf = DynamicBufferLib.p(buf, '">COLOUR PALETTE: <tspan fill="');
        buf = DynamicBufferLib.p(buf, bytes(ac));
        buf = DynamicBufferLib.p(buf, '">');
        buf = DynamicBufferLib.p(buf, bytes(LibString.toString(uint256(v.paletteIdx) + 1)));
        buf = DynamicBufferLib.p(buf, "</tspan></text>");
        buf = DynamicBufferLib.p(buf, '<text x="54" y="270" fill="');
        buf = DynamicBufferLib.p(buf, bytes(tx));
        buf = DynamicBufferLib.p(buf, '">CHARACTER SET: <tspan fill="');
        buf = DynamicBufferLib.p(buf, bytes(ac));
        buf = DynamicBufferLib.p(buf, '">');
        buf = DynamicBufferLib.p(buf, bytes(LibString.toString(uint256(v.charSetIdx) + 1)));
        buf = DynamicBufferLib.p(buf, "</tspan></text>");
        buf = DynamicBufferLib.p(buf, '<text x="54" y="305" fill="');
        buf = DynamicBufferLib.p(buf, bytes(tx));
        buf = DynamicBufferLib.p(buf, '">BEHAVIOUR SET: <tspan fill="');
        buf = DynamicBufferLib.p(buf, bytes(ac));
        buf = DynamicBufferLib.p(buf, '">');
        buf = DynamicBufferLib.p(buf, bytes(LibString.toString(uint256(v.behaviourIdx) + 1)));
        buf = DynamicBufferLib.p(buf, "</tspan></text>");

        _sphere(buf, palettes, v.paletteIdx, palette);

        _row(buf, 440, "BASE RADIUS",         _fixI32(eff[0]),  tx, ac);
        _row(buf, 475, "ASPECT RATIO",        _fixI32(eff[1]),  tx, ac);
        _row(buf, 510, "STEP SIZE",           _fixI32(eff[2]),  tx, ac);
        _row(buf, 545, "MOVE SPEED",          _fixI32(eff[3]),  tx, ac);
        _row(buf, 580, "MAX MOVE DISTANCE",   _fixI32(eff[4]),  tx, ac);
        _row2(buf, 615, "X/Y BIAS",           _fixI32(eff[5]),  _fixI32(eff[6]),  tx, ac);
        _row2(buf, 650, "MIN/MAX ROTATION SPEED", _fixI32(eff[7]), _fixI32(eff[8]), tx, ac);
        _row(buf, 685, "ROTATION SMOOTHNESS", _fixI32(eff[9]),  tx, ac);
        _row(buf, 720, "MAX ROTATION ANGLE",  _fixI32(eff[10]), tx, ac);
        _row2(buf, 755, "BASE/EXTRA DEFORM STRENGTH", _fixI32(eff[11]), _fixI32(eff[12]), tx, ac);
        _row3(buf, 790, "DEFORM FREQUENCY/COMPLEXITY/SMOOTHNESS",
            _fixI32(eff[13]), _fixI32(eff[14]), _fixI32(eff[15]), tx, ac);
        _row(buf, 825, "DRIPPINESS",          _fixI32(eff[16]), tx, ac);
        _row(buf, 860, "TIME SPEED",          _fixI32(eff[17]), tx, ac);
        _row2(buf, 895, "PERSPECTIVE DISTANCE/STRENGTH", _fixI32(eff[18]), _fixI32(eff[19]), tx, ac);
        _row(buf, 930, "BEHAVIOR CHANGE TIME",_fixI32(eff[20]), tx, ac);

        buf = DynamicBufferLib.p(buf, "</svg>");
        return buf.data;
    }

    function _sphere(
        DynamicBufferLib.DynamicBuffer memory buf,
        bytes memory palettes,
        uint8 paletteIdx,
        string memory palette
    ) internal pure {
        bytes[SPHERE_SHADES] memory tail;
        bytes memory paletteBytes = bytes(palette);
        uint256[SPHERE_SHADES] memory charOff;
        uint256[SPHERE_SHADES] memory charLen;
        _scanCharOffsets(paletteBytes, charOff, charLen);
        for (uint256 s; s < SPHERE_SHADES; s++) {
            DynamicBufferLib.DynamicBuffer memory t;
            t = DynamicBufferLib.p(t, '" fill="');
            t = DynamicBufferLib.p(t, bytes(RenderHelpers.toHexColor(_voidlingColor(palettes, paletteIdx, s))));
            t = DynamicBufferLib.p(t, '">');
            t = DynamicBufferLib.p(t, _xmlEscape(_sliceFromOffset(paletteBytes, charOff[s], charLen[s])));
            t = DynamicBufferLib.p(t, '</tspan>');
            tail[s] = t.data;
        }

        bytes[SPHERE_COLS] memory xStr;
        for (uint256 c; c < SPHERE_COLS; c++) {
            xStr[c] = bytes(LibString.toString(SPHERE_X0 + c * SPHERE_STEP_X));
        }

        bytes memory data = SPHERE_DATA;

        for (uint256 row; row < SPHERE_ROWS; row++) {
            bool rowOpened;
            uint256 rowNibBase = row * SPHERE_COLS;
            for (uint256 col; col < SPHERE_COLS; col++) {
                uint256 nibIdx = rowNibBase + col;
                uint8 packed = uint8(data[nibIdx >> 1]);
                uint8 nibble = (nibIdx & 1) == 0 ? (packed >> 4) : (packed & 0x0f);
                if (nibble == 0) continue;
                if (!rowOpened) {
                    buf = DynamicBufferLib.p(buf, '<text y="');
                    buf = DynamicBufferLib.p(buf, bytes(LibString.toString(SPHERE_Y0 + row * SPHERE_STEP_Y)));
                    buf = DynamicBufferLib.p(buf, '">');
                    rowOpened = true;
                }
                buf = DynamicBufferLib.p(buf, '<tspan x="');
                buf = DynamicBufferLib.p(buf, xStr[col]);
                buf = DynamicBufferLib.p(buf, tail[nibble - 1]);
            }
            if (rowOpened) buf = DynamicBufferLib.p(buf, "</text>");
        }
    }

    function _scanCharOffsets(
        bytes memory palette,
        uint256[SPHERE_SHADES] memory offsets,
        uint256[SPHERE_SHADES] memory lens
    ) internal pure {
        uint256 i;
        uint256 chIdx;
        while (i < palette.length && chIdx < SPHERE_SHADES) {
            uint256 cl = RenderHelpers.utf8Len(uint8(palette[i]));
            offsets[chIdx] = i;
            lens[chIdx] = cl;
            i += cl;
            chIdx += 1;
        }
    }

    function _sliceFromOffset(bytes memory src, uint256 offset, uint256 len) internal pure returns (bytes memory out) {
        out = new bytes(len);
        for (uint256 i; i < len; i++) out[i] = src[offset + i];
    }

    function _row(
        DynamicBufferLib.DynamicBuffer memory buf,
        uint256 y,
        string memory label,
        string memory val,
        string memory tx_,
        string memory ac
    ) internal pure {
        buf = DynamicBufferLib.p(buf, '<text x="54" y="');
        buf = DynamicBufferLib.p(buf, bytes(LibString.toString(y)));
        buf = DynamicBufferLib.p(buf, '" fill="');
        buf = DynamicBufferLib.p(buf, bytes(tx_));
        buf = DynamicBufferLib.p(buf, '">');
        buf = DynamicBufferLib.p(buf, bytes(label));
        buf = DynamicBufferLib.p(buf, ': <tspan fill="');
        buf = DynamicBufferLib.p(buf, bytes(ac));
        buf = DynamicBufferLib.p(buf, '">');
        buf = DynamicBufferLib.p(buf, bytes(val));
        buf = DynamicBufferLib.p(buf, "</tspan></text>");
    }

    function _row2(
        DynamicBufferLib.DynamicBuffer memory buf,
        uint256 y,
        string memory label,
        string memory a,
        string memory bb,
        string memory tx_,
        string memory ac
    ) internal pure {
        buf = DynamicBufferLib.p(buf, '<text x="54" y="');
        buf = DynamicBufferLib.p(buf, bytes(LibString.toString(y)));
        buf = DynamicBufferLib.p(buf, '" fill="');
        buf = DynamicBufferLib.p(buf, bytes(tx_));
        buf = DynamicBufferLib.p(buf, '">');
        buf = DynamicBufferLib.p(buf, bytes(label));
        buf = DynamicBufferLib.p(buf, ': <tspan fill="');
        buf = DynamicBufferLib.p(buf, bytes(ac));
        buf = DynamicBufferLib.p(buf, '">');
        buf = DynamicBufferLib.p(buf, bytes(a));
        buf = DynamicBufferLib.p(buf, "/");
        buf = DynamicBufferLib.p(buf, bytes(bb));
        buf = DynamicBufferLib.p(buf, "</tspan></text>");
    }

    function _row3(
        DynamicBufferLib.DynamicBuffer memory buf,
        uint256 y,
        string memory label,
        string memory a,
        string memory bb,
        string memory c,
        string memory tx_,
        string memory ac
    ) internal pure {
        buf = DynamicBufferLib.p(buf, '<text x="54" y="');
        buf = DynamicBufferLib.p(buf, bytes(LibString.toString(y)));
        buf = DynamicBufferLib.p(buf, '" fill="');
        buf = DynamicBufferLib.p(buf, bytes(tx_));
        buf = DynamicBufferLib.p(buf, '">');
        buf = DynamicBufferLib.p(buf, bytes(label));
        buf = DynamicBufferLib.p(buf, ': <tspan fill="');
        buf = DynamicBufferLib.p(buf, bytes(ac));
        buf = DynamicBufferLib.p(buf, '">');
        buf = DynamicBufferLib.p(buf, bytes(a));
        buf = DynamicBufferLib.p(buf, "/");
        buf = DynamicBufferLib.p(buf, bytes(bb));
        buf = DynamicBufferLib.p(buf, "/");
        buf = DynamicBufferLib.p(buf, bytes(c));
        buf = DynamicBufferLib.p(buf, "</tspan></text>");
    }

    function _shortAddr(address a) internal pure returns (bytes memory out) {
        bytes memory full = bytes(LibString.toHexString(a));
        out = new bytes(14);
        for (uint256 i; i < 14; i++) out[i] = full[i];
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
            uint32 mag = uint32(-v);
            return string.concat("-", RenderHelpers.fix(uint256(mag)));
        }
        return RenderHelpers.fix(uint256(uint32(v)));
    }

    function _voidlingColor(bytes memory palettes, uint8 paletteIdx, uint256 charIdx) internal pure returns (bytes4) {
        uint256 off = uint256(paletteIdx) * PALETTE_BYTES + charIdx * 4;
        return bytes4(uint32(RenderHelpers.readU32(palettes, off)));
    }

    function _namedColor(bytes memory palettes, uint8 paletteIdx, uint256 namedIdx) internal pure returns (string memory) {
        uint256 off = uint256(paletteIdx) * PALETTE_BYTES + MAX_VOIDLING * 4 + namedIdx * 4;
        return RenderHelpers.toHexColor(bytes4(uint32(RenderHelpers.readU32(palettes, off))));
    }

    function _charSet(bytes memory charSets, bytes memory charOffs, uint8 idx) internal pure returns (string memory) {
        uint256 off = RenderHelpers.readU16(charOffs, uint256(idx) * 2);
        return RenderHelpers.readLengthPrefixed(charSets, off);
    }
}