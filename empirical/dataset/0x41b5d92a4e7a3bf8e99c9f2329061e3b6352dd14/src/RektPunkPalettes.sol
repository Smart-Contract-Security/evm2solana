// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title RektPunk color palettes
/// @notice Pure library exposing all color palettes used by the renderer.
///         Colors are packed as bytes3 (RGB). Mirrors the HTML constants 1:1.
library RektPunkPalettes {
    // ----- Backgrounds: 12 single colors -----
    function bg(uint256 i) internal pure returns (bytes3) {
        if (i == 0)  return 0xff7675;
        if (i == 1)  return 0x55efc4;
        if (i == 2)  return 0x74b9ff;
        if (i == 3)  return 0xfdcb6e;
        if (i == 4)  return 0xa29bfe;
        if (i == 5)  return 0xff4757;
        if (i == 6)  return 0x2ed573;
        if (i == 7)  return 0x1e90ff;
        if (i == 8)  return 0x87ceeb;
        if (i == 9)  return 0x98ff98;
        if (i == 10) return 0xff69b4;
        return 0xffd700;
    }

    // ----- Skull palettes: 12 × 6 shades -----
    function skull(uint256 i, uint256 shade) internal pure returns (bytes3) {
        if (i == 0)  return [bytes3(0xf0e8d8),0xe8dece,0xddd3c0,0xd0c5b2,0xc0b5a0,0xb0a590][shade];
        if (i == 1)  return [bytes3(0xd8e8d0),0xccddc4,0xb8ccb0,0xa4bca0,0x90aa88,0x80987a][shade];
        if (i == 2)  return [bytes3(0xd8e4f0),0xc8d8e8,0xb0c4d8,0x98b0c4,0x80a0b4,0x6890a4][shade];
        if (i == 3)  return [bytes3(0xf0e8d8),0xe8dece,0xddd3c0,0xd0c5b2,0xc0b5a0,0xb0a590][shade];
        if (i == 4)  return [bytes3(0xe8e0f0),0xdcd4e8,0xccc0d8,0xbcb0c8,0xa8a0b8,0x9890a8][shade];
        if (i == 5)  return [bytes3(0xf0e0e0),0xe8d0d0,0xddc0c0,0xd0b0b0,0xc0a0a0,0xb09090][shade];
        if (i == 6)  return [bytes3(0xe0e0e0),0xd0d0d0,0xc0c0c0,0xb0b0b0,0xa0a0a0,0x909090][shade];
        if (i == 7)  return [bytes3(0xd0c8c0),0xc0b8b0,0xb0a8a0,0xa09890,0x908880,0x807870][shade];
        if (i == 8)  return [bytes3(0xc0f0d8),0xa0e8b8,0x80d098,0x60b878,0x40a058,0x208838][shade];
        if (i == 9)  return [bytes3(0xf0c0c0),0xe8a0a0,0xd08080,0xb86060,0xa04040,0x882020][shade];
        if (i == 10) return [bytes3(0xe0c0f0),0xd0a0e8,0xb880d0,0xa060b8,0x8840a0,0x702088][shade];
        return [bytes3(0xf0e0b0),0xe8d098,0xd0b880,0xb8a068,0xa08850,0x887038][shade];
    }

    // ----- Eye palettes: 12 × 4 shades -----
    function eye(uint256 i, uint256 shade) internal pure returns (bytes3) {
        if (i == 0)  return [bytes3(0xff0040),0xcc0033,0xff3366,0x990029][shade];
        if (i == 1)  return [bytes3(0x00ff88),0x00cc6a,0x66ffbb,0x009955][shade];
        if (i == 2)  return [bytes3(0x00aaff),0x0088cc,0x66ccff,0x006699][shade];
        if (i == 3)  return [bytes3(0xffc832),0xcc9900,0xffe066,0x997700][shade];
        if (i == 4)  return [bytes3(0xb450ff),0x9030dd,0xd080ff,0x7020bb][shade];
        if (i == 5)  return [bytes3(0xff2020),0xcc1818,0xff5050,0x991010][shade];
        if (i == 6)  return [bytes3(0xff69b4),0xcc5490,0xff99cc,0x993f6c][shade];
        if (i == 7)  return [bytes3(0x666666),0x444444,0x888888,0x333333][shade];
        if (i == 8)  return [bytes3(0x39ff14),0x32cc11,0x25990c,0x196608][shade];
        if (i == 9)  return [bytes3(0xff5f1f),0xcc4c18,0x993912,0x66260c][shade];
        if (i == 10) return [bytes3(0x8f00ff),0x7200cc,0x550099,0x390066][shade];
        return [bytes3(0xffffff),0xcccccc,0x999999,0x666666][shade];
    }

    // ----- Hoodie palettes: 12 × 6 shades -----
    function hoodie(uint256 i, uint256 shade) internal pure returns (bytes3) {
        if (i == 0)  return [bytes3(0x1e1e3a),0x16162e,0x101028,0x0c0c20,0x08081a,0x1a1a35][shade];
        if (i == 1)  return [bytes3(0x0e2a1a),0x0a2214,0x081a10,0x06140c,0x041008,0x10301e][shade];
        if (i == 2)  return [bytes3(0x0e1a2e),0x0a1424,0x08101c,0x060c16,0x040810,0x102030][shade];
        if (i == 3)  return [bytes3(0x1a1428),0x141020,0x100c1a,0x0c0814,0x08060e,0x201830][shade];
        if (i == 4)  return [bytes3(0x2a1418),0x201010,0x1a0c0c,0x140808,0x100606,0x301418][shade];
        if (i == 5)  return [bytes3(0x2a2a30),0x222228,0x1c1c22,0x16161c,0x101016,0x30303a][shade];
        if (i == 6)  return [bytes3(0x1a2018),0x142014,0x101a10,0x0c140c,0x081008,0x20281e][shade];
        if (i == 7)  return [bytes3(0x1a1a30),0x181830,0x141428,0x101020,0x0c0c18,0x222238][shade];
        if (i == 8)  return [bytes3(0xfff030),0xdccc28,0xb8aa20,0x948818,0x706610,0x4c4408][shade];
        if (i == 9)  return [bytes3(0xff33cc),0xcc28a3,0x991e7a,0x661451,0x330a28,0xff66d9][shade];
        if (i == 10) return [bytes3(0x33ff33),0x28cc28,0x1e991e,0x146614,0x0a330a,0x66ff66][shade];
        return [bytes3(0x3333ff),0x2828cc,0x1e1e99,0x141466,0x0a0a33,0x6666ff][shade];
    }
}
