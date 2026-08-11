// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IR1 {
    function render(uint8 ptype, uint8 bgStyle, uint8 bgPal) external pure returns (string memory);
}

interface IR2 {
    function render(uint8 ptype) external pure returns (string memory);
}

interface IR3 {
    function render(uint8 hat, uint8 hatColor, uint8 eye, uint8 eyeColor, uint8 mouth, uint8 acc, uint8 accColor)
        external pure returns (string memory);
}

contract PlantPunksR4 {
    address public r1;
    address public r2;
    address public r3;
    address public owner;

    constructor() { owner = msg.sender; }

    function setRenderers(address _r1, address _r2, address _r3) external {
        require(msg.sender == owner);
        r1 = _r1; r2 = _r2; r3 = _r3;
    }

    struct Traits {
        uint8 ptype;
        uint8 bgStyle;
        uint8 bgPal;
        uint8 hat;
        uint8 hatColor;
        uint8 eye;
        uint8 eyeColor;
        uint8 mouth;
        uint8 acc;
        uint8 accColor;
    }

    function decodeTraits(uint256 tokenId, uint256 seed) public pure returns (Traits memory t) {
        uint256 h = uint256(keccak256(abi.encodePacked(tokenId, seed)));
        t.ptype    = uint8(h % 8);  h >>= 4;
        t.bgStyle  = uint8(h % 6);  h >>= 4;
        t.bgPal    = uint8(h % 8);  h >>= 4;
        t.hat      = uint8(h % 8);  h >>= 4;
        t.hatColor = uint8(h % 8);  h >>= 4;
        t.eye      = uint8(h % 8);  h >>= 4;
        t.eyeColor = uint8(h % 8);  h >>= 4;
        t.mouth    = uint8(h % 8);  h >>= 4;
        t.acc      = uint8(h % 8);  h >>= 4;
        t.accColor = uint8(h % 4);
    }

    function _plantName(uint8 i) internal pure returns (string memory) {
        if (i == 0) return "Cactus";
        if (i == 1) return "Shroom";
        if (i == 2) return "Flower";
        if (i == 3) return "Venus";
        if (i == 4) return "Fern";
        if (i == 5) return "Crystal";
        if (i == 6) return "Moss";
        return "Dead";
    }
    function _bgName(uint8 i) internal pure returns (string memory) {
        if (i == 0) return "Solid";
        if (i == 1) return "Grid";
        if (i == 2) return "Diagonal";
        if (i == 3) return "Scanline";
        if (i == 4) return "Radial";
        return "Flat";
    }
    function _hatName(uint8 i) internal pure returns (string memory) {
        if (i == 0) return "Mohawk";
        if (i == 1) return "Spikes";
        if (i == 2) return "Crown";
        if (i == 3) return "Beanie";
        if (i == 4) return "Cap";
        if (i == 5) return "Halo";
        if (i == 6) return "None";
        return "Bandana";
    }
    function _eyeName(uint8 i) internal pure returns (string memory) {
        if (i == 0) return "Angry";
        if (i == 1) return "Lazy";
        if (i == 2) return "Wide";
        if (i == 3) return "X";
        if (i == 4) return "Star";
        if (i == 5) return "Dollar";
        if (i == 6) return "Skull";
        return "Heart";
    }
    function _mouthName(uint8 i) internal pure returns (string memory) {
        if (i == 0) return "Smirk";
        if (i == 1) return "Grin";
        if (i == 2) return "Frown";
        if (i == 3) return "Fangs";
        if (i == 4) return "Zipper";
        if (i == 5) return "Joint";
        if (i == 6) return "Tongue";
        return "None";
    }
    function _accName(uint8 i) internal pure returns (string memory) {
        if (i == 0) return "Chain";
        if (i == 1) return "Piercing";
        if (i == 2) return "Glasses";
        if (i == 3) return "Earring";
        if (i == 4) return "Tattoo";
        if (i == 5) return "None";
        if (i == 6) return "Collar";
        return "Badge";
    }

    function buildSVG(Traits memory t) public view returns (string memory) {
        string memory bg = IR1(r1).render(t.ptype, t.bgStyle, t.bgPal);
        string memory plant = t.ptype <= 2 ? "" : IR2(r2).render(t.ptype);
        string memory traits = IR3(r3).render(t.hat, t.hatColor, t.eye, t.eyeColor, t.mouth, t.acc, t.accColor);
        return string(abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 140 140" shape-rendering="crispEdges">',
            bg, plant, traits, '</svg>'
        ));
    }

    function buildMetadata(uint256 tokenId, Traits memory t, string memory svg)
        public pure returns (string memory) {
        string memory attrs = string(abi.encodePacked(
            '[{"trait_type":"Plant","value":"',      _plantName(t.ptype),  '"},',
            '{"trait_type":"Background","value":"',  _bgName(t.bgStyle),   '"},',
            '{"trait_type":"Hat","value":"',         _hatName(t.hat),      '"},',
            '{"trait_type":"Eyes","value":"',        _eyeName(t.eye),      '"},',
            '{"trait_type":"Mouth","value":"',       _mouthName(t.mouth),  '"},',
            '{"trait_type":"Accessory","value":"',   _accName(t.acc),      '"}]'
        ));
        string memory json = string(abi.encodePacked(
            '{"name":"Plant Punk #', _ts(tokenId), '",',
            '"description":"Plant Punks - Fully on-chain generative NFT collection.",',
            '"image":"data:image/svg+xml;base64,', _b64(bytes(svg)), '",',
            '"attributes":', attrs, '}'
        ));
        return string(abi.encodePacked("data:application/json;base64,", _b64(bytes(json))));
    }

    function tokenURI(uint256 tokenId, uint256 seed) external view returns (string memory) {
        Traits memory t = decodeTraits(tokenId, seed);
        string memory svg = buildSVG(t);
        string memory attrs = string(abi.encodePacked(
            '[{"trait_type":"Plant","value":"',      _plantName(t.ptype),  '"},',
            '{"trait_type":"Background","value":"',  _bgName(t.bgStyle),   '"},',
            '{"trait_type":"Hat","value":"',         _hatName(t.hat),      '"},',
            '{"trait_type":"Eyes","value":"',        _eyeName(t.eye),      '"},',
            '{"trait_type":"Mouth","value":"',       _mouthName(t.mouth),  '"},',
            '{"trait_type":"Accessory","value":"',   _accName(t.acc),      '"}]'
        ));
        string memory imgB64 = _b64(bytes(svg));
        string memory json = string(abi.encodePacked(
            '{"name":"Plant Punk #', _ts(tokenId), '",',
            '"description":"Plant Punks - Fully on-chain generative NFT collection.",',
            '"image":"data:image/svg+xml;base64,', imgB64, '",',
            '"attributes":', attrs, '}'
        ));
        return string(abi.encodePacked("data:application/json;base64,", _b64(bytes(json))));
    }

    // ─── Base64 ──────────────────────────────────────────
    function _b64(bytes memory data) internal pure returns (string memory) {
        if (data.length == 0) return "";
        bytes memory table = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        uint256 len = data.length;
        uint256 encodedLen = 4 * ((len + 2) / 3);
        bytes memory result = new bytes(encodedLen);
        uint256 i;
        uint256 j;
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