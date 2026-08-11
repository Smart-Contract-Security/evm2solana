// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

interface IR1 {
    function render(string memory bin, uint8 rarity, uint8 bgStyle, uint8 bgSeed, uint8 hatType)
        external pure returns (string memory);
}

interface IR2 {
    function render(uint8 eye, uint8 mouth, uint8 clothes, uint8 acc)
        external pure returns (string memory);
}

contract BinaryPunksR3 {
    address public r1;
    address public r2;
    address public owner;

    constructor() { owner = msg.sender; }

    function setRenderers(address _r1, address _r2) external {
        require(msg.sender == owner);
        r1 = _r1;
        r2 = _r2;
    }

    // 20 secret words
    string[20] internal WORDS = [
        "PUNK","DEGEN","REKT","MOON","WAGMI",
        "NGMI","BASED","CHAD","FREN","ALPHA",
        "ANON","HODL","VIBE","RARE","GOAT",
        "FLEX","ETH","BTC","SOL","WEB3"
    ];

    string[10] internal HAT_NAMES   = ["Mohawk","Spikes","Crown","Cap","Beanie","Hood","Headset","Antenna","Bandana","None"];
    string[8]  internal EYE_NAMES   = ["Normal","Angry","Wide","X","Heart","Star","Scan","Dollar"];
    string[8]  internal MOUTH_NAMES = ["Smirk","Grin","Frown","Fangs","Zipper","Data","Mask","None"];
    string[8]  internal CLOTH_NAMES = ["Hoodie","Jacket","Armor","T-Shirt","Vest","None","None","None"];
    string[10] internal ACC_NAMES   = ["Chain","Glasses","Earring","Piercing","Collar","Badge","USB","Tattoo","Chip","None"];
    string[3]  internal RARITY_NAMES = ["Common","Corrupted","Rainbow"];
    string[5]  internal BG_NAMES   = ["Solid","Grid","Dots","Scanline","Lines"];

    struct Traits {
        uint8 word;      // 0-19
        uint8 rarity;    // 0=common 1=corrupted 2=rainbow
        uint8 bgStyle;   // 0-4
        uint8 bgSeed;    // 0-7
        uint8 hat;       // 0-9
        uint8 eye;       // 0-7
        uint8 mouth;     // 0-7
        uint8 clothes;   // 0-7
        uint8 acc;       // 0-9
    }

    function decodeTraits(uint256 tokenId, uint256 seed) public pure returns (Traits memory t) {
        uint256 h = uint256(keccak256(abi.encodePacked(tokenId, seed)));
        // rarity weighted: 2% rainbow, 8% corrupted, 90% common
        uint8 rv = uint8(h % 100);
        if (rv < 2) t.rarity = 2;
        else if (rv < 10) t.rarity = 1;
        else t.rarity = 0;
        h >>= 8;
        t.word    = uint8(h % 20);    h >>= 5;
        t.bgStyle = uint8(h % 5);     h >>= 4;
        t.bgSeed  = uint8(h % 8);     h >>= 4;
        t.hat     = uint8(h % 10);    h >>= 4;
        t.eye     = uint8(h % 8);     h >>= 4;
        t.mouth   = uint8(h % 8);     h >>= 4;
        t.clothes = uint8(h % 8);     h >>= 4;
        t.acc     = uint8(h % 10);
    }

    function _wordToBinary(string memory word) internal pure returns (string memory) {
        bytes memory b = bytes(word);
        bytes memory result = new bytes(b.length * 8);
        for (uint256 i = 0; i < b.length; i++) {
            uint8 ch = uint8(b[i]);
            for (uint256 j = 0; j < 8; j++) {
                result[i * 8 + j] = (ch & (0x80 >> j)) != 0 ? bytes1('1') : bytes1('0');
            }
        }
        return string(result);
    }

    function _wordName(uint8 idx) internal view returns (string memory) {
        return WORDS[idx];
    }
    function _hatName(uint8 i) internal view returns (string memory) { return HAT_NAMES[i]; }
    function _eyeName(uint8 i) internal view returns (string memory) { return EYE_NAMES[i]; }
    function _mouthName(uint8 i) internal view returns (string memory) { return MOUTH_NAMES[i]; }
    function _clothName(uint8 i) internal view returns (string memory) { return CLOTH_NAMES[i]; }
    function _accName(uint8 i) internal view returns (string memory) { return ACC_NAMES[i]; }
    function _rarityName(uint8 i) internal view returns (string memory) { return RARITY_NAMES[i]; }
    function _bgName(uint8 i) internal view returns (string memory) { return BG_NAMES[i]; }

    function buildSVG(Traits memory t) public view returns (string memory) {
        string memory bin = _wordToBinary(WORDS[t.word]);
        string memory layer1 = IR1(r1).render(bin, t.rarity, t.bgStyle, t.bgSeed, t.hat);
        string memory layer2 = IR2(r2).render(t.eye, t.mouth, t.clothes, t.acc);
        return string(abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120" shape-rendering="crispEdges">',
            layer1, layer2, '</svg>'
        ));
    }

    function buildMetadata(uint256 tokenId, Traits memory t, string memory svg)
        public view returns (string memory) {
        string memory attrs = string(abi.encodePacked(
            '[{"trait_type":"Rarity","value":"',     _rarityName(t.rarity),  '"},',
            '{"trait_type":"Secret Word","value":"', _wordName(t.word),      '"},',
            '{"trait_type":"Background","value":"',  _bgName(t.bgStyle),     '"},',
            '{"trait_type":"Hat","value":"',         _hatName(t.hat),        '"},',
            '{"trait_type":"Eyes","value":"',        _eyeName(t.eye),        '"},',
            '{"trait_type":"Mouth","value":"',       _mouthName(t.mouth),    '"},',
            '{"trait_type":"Clothes","value":"',     _clothName(t.clothes),  '"},',
            '{"trait_type":"Accessory","value":"',   _accName(t.acc),        '"}]'
        ));
        string memory json = string(abi.encodePacked(
            '{"name":"Binary Punk #', _ts(tokenId), '",',
            '"description":"Binary Punks - 10,000 fully on-chain generative NFTs. Each body encodes a secret binary message.",',
            '"image":"data:image/svg+xml;base64,', _b64(bytes(svg)), '",',
            '"attributes":', attrs, '}'
        ));
        return string(abi.encodePacked("data:application/json;base64,", _b64(bytes(json))));
    }

    // Decode function — returns the secret word for a token
    function decodeSecret(uint256 tokenId, uint256 seed) external view returns (string memory) {
        Traits memory t = decodeTraits(tokenId, seed);
        return WORDS[t.word];
    }

    function tokenURI(uint256 tokenId, uint256 seed) external view returns (string memory) {
        Traits memory t = decodeTraits(tokenId, seed);
        string memory svg = buildSVG(t);
        return buildMetadata(tokenId, t, svg);
    }

    // ── Base64 ──────────────────────────────────────────────
    function _b64(bytes memory data) internal pure returns (string memory) {
        if (data.length == 0) return "";
        bytes memory table = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        uint256 len = data.length;
        uint256 encodedLen = 4 * ((len + 2) / 3);
        bytes memory result = new bytes(encodedLen);
        uint256 i; uint256 j;
        for (i = 0; i + 2 < len; i += 3) {
            uint256 a = uint8(data[i]);
            uint256 b = uint8(data[i+1]);
            uint256 c = uint8(data[i+2]);
            result[j]   = table[a >> 2];
            result[j+1] = table[((a & 3) << 4) | (b >> 4)];
            result[j+2] = table[((b & 15) << 2) | (c >> 6)];
            result[j+3] = table[c & 63];
            j += 4;
        }
        if (i < len) {
            uint256 a = uint8(data[i]);
            result[j] = table[a >> 2];
            if (i + 1 < len) {
                uint256 b = uint8(data[i+1]);
                result[j+1] = table[((a & 3) << 4) | (b >> 4)];
                result[j+2] = table[(b & 15) << 2];
            } else {
                result[j+1] = table[(a & 3) << 4];
                result[j+2] = "=";
            }
            result[j+3] = "=";
        }
        return string(result);
    }

    function _ts(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        uint256 tmp = v; uint256 len = 0;
        while (tmp > 0) { len++; tmp /= 10; }
        bytes memory buf = new bytes(len);
        tmp = v;
        for (uint256 i = len; i > 0; i--) { buf[i-1] = bytes1(uint8(48 + tmp % 10)); tmp /= 10; }
        return string(buf);
    }
}
